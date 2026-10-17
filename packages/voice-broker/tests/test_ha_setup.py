"""What voice-broker-ha-setup would create, from Home Assistant's state: create-only, never a change."""

from __future__ import annotations

import asyncio

import pytest
from voice_broker.ha_setup import (
    DEFAULT_NAME,
    DEFAULT_SOURCE_PIPELINE,
    SetupError,
    State,
    _backup,
    plan,
    wait_for_agent,
)

REMOTE = {
    "id": DEFAULT_SOURCE_PIPELINE,
    "name": "Remote",
    "language": "en",
    "stt_engine": "stt.groq",
    "stt_language": "en",
    "conversation_engine": "conversation.chatgpt",
    "conversation_language": "*",
    "tts_engine": "tts.elevenlabs",
    "tts_language": "en",
    "tts_voice": "voice",
    "wake_word_entity": None,
    "wake_word_id": None,
    "prefer_local_intents": True,
}
MAIN_AGENT = {"subentry_id": "01MAIN", "subentry_type": "conversation", "title": "Main Assistant"}
HOME_AGENT = {"subentry_id": "01HOME", "subentry_type": "conversation", "title": DEFAULT_NAME}


def state(pipelines=(REMOTE,), subentries=(MAIN_AGENT,), entries=1, agents=None) -> State:
    return State(
        list(pipelines),
        DEFAULT_SOURCE_PIPELINE,
        [(f"01ENTRY{i}", list(subentries)) for i in range(entries)],
        agents
        if agents is not None
        else {"01MAIN": "conversation.chatgpt", "01HOME": "conversation.voice_broker_home"},
    )


def test_nothing_there_yet_creates_the_agent_and_a_pipeline_with_remotes_speech_recognition_and_no_tts():
    steps = plan(state(), DEFAULT_NAME, DEFAULT_SOURCE_PIPELINE)
    assert steps.create_agent and steps.agent_entity is None and steps.entry_id == "01ENTRY0"
    assert steps.pipeline == {
        "name": DEFAULT_NAME,
        "language": "en",
        # The speech recognition, English included, stays exactly as "Remote" has it.
        "stt_engine": "stt.groq",
        "stt_language": "en",
        "conversation_language": "*",
        "prefer_local_intents": True,
        "tts_engine": None,
        "tts_language": None,
        "tts_voice": None,
        "wake_word_entity": None,
        "wake_word_id": None,
    }


def test_an_existing_agent_is_used_as_it_is():
    steps = plan(state(subentries=(MAIN_AGENT, HOME_AGENT)), DEFAULT_NAME, DEFAULT_SOURCE_PIPELINE)
    assert not steps.create_agent and steps.agent_entity == "conversation.voice_broker_home"
    assert steps.pipeline is not None


def test_everything_in_place_plans_nothing():
    pipeline = {
        **REMOTE,
        "id": "01NEW",
        "name": DEFAULT_NAME,
        "conversation_engine": "conversation.voice_broker_home",
        "tts_engine": None,
        "tts_language": None,
        "tts_voice": None,
    }
    steps = plan(
        state(pipelines=(REMOTE, pipeline), subentries=(MAIN_AGENT, HOME_AGENT)), DEFAULT_NAME, DEFAULT_SOURCE_PIPELINE
    )
    assert not steps.create_agent and steps.pipeline is None


@pytest.mark.parametrize(
    ("kwargs", "match"),
    [
        # An existing pipeline of that name on another agent is reported, never rewritten.
        (
            {
                "pipelines": (REMOTE, {**REMOTE, "id": "01X", "name": DEFAULT_NAME}),
                "subentries": (MAIN_AGENT, HOME_AGENT),
            },
            "exists with different",
        ),
        ({"pipelines": ({**REMOTE, "id": "01OTHER"},)}, "source pipeline"),
        ({"entries": 2}, "expected one"),
        ({"entries": 0}, "expected one"),
        ({"subentries": (MAIN_AGENT, HOME_AGENT, {**HOME_AGENT, "subentry_id": "01HOME2"})}, "2 agents"),
        ({"subentries": (MAIN_AGENT, HOME_AGENT), "agents": {}}, "no conversation entity"),
    ],
)
def test_anything_it_must_not_touch_stops_it(kwargs, match):
    with pytest.raises(SetupError, match=match):
        plan(state(**kwargs), DEFAULT_NAME, DEFAULT_SOURCE_PIPELINE)


def _reads(*states: State):
    remaining = list(states)

    async def read() -> State:
        return remaining.pop(0) if len(remaining) > 1 else remaining[0]

    return read


def test_the_pipeline_waits_for_the_new_agents_entity_which_home_assistant_adds_after_the_flow_returns():
    # 2026-10-17: right after the flow, the subentry was there but its entity was not.
    created = state(subentries=(MAIN_AGENT, HOME_AGENT), agents={"01MAIN": "conversation.chatgpt"})
    ready = state(subentries=(MAIN_AGENT, HOME_AGENT))
    steps = asyncio.run(
        wait_for_agent(_reads(created, created, ready), DEFAULT_NAME, DEFAULT_SOURCE_PIPELINE, interval_s=0)
    )
    assert steps.agent_entity == "conversation.voice_broker_home" and steps.pipeline is not None


def test_an_entity_that_never_appears_stops_it_before_any_pipeline():
    created = state(subentries=(MAIN_AGENT, HOME_AGENT), agents={"01MAIN": "conversation.chatgpt"})
    with pytest.raises(SetupError, match="no conversation entity after"):
        asyncio.run(wait_for_agent(_reads(created), DEFAULT_NAME, DEFAULT_SOURCE_PIPELINE, timeout_s=0, interval_s=0))


def test_an_agent_gone_after_its_creation_stops_it():
    with pytest.raises(SetupError, match="missing after it was created"):
        asyncio.run(wait_for_agent(_reads(state()), DEFAULT_NAME, DEFAULT_SOURCE_PIPELINE, interval_s=0))


def test_two_backups_within_a_second_do_not_collide(tmp_path):
    first, second = _backup(tmp_path, state()), _backup(tmp_path, state())
    assert first != second and first.exists() and second.exists()
    assert oct(first.stat().st_mode & 0o777) == "0o600"


def test_an_existing_pipeline_waits_for_the_new_agents_entity_before_it_is_compared():
    pipeline = {
        **REMOTE,
        "id": "01NEW",
        "name": DEFAULT_NAME,
        "conversation_engine": "conversation.voice_broker_home",
        "tts_engine": None,
        "tts_language": None,
        "tts_voice": None,
    }
    created = state(
        pipelines=(REMOTE, pipeline), subentries=(MAIN_AGENT, HOME_AGENT), agents={"01MAIN": "conversation.chatgpt"}
    )
    ready = state(pipelines=(REMOTE, pipeline), subentries=(MAIN_AGENT, HOME_AGENT))
    steps = asyncio.run(wait_for_agent(_reads(created, ready), DEFAULT_NAME, DEFAULT_SOURCE_PIPELINE, interval_s=0))
    assert steps.agent_entity == "conversation.voice_broker_home" and steps.pipeline is None
