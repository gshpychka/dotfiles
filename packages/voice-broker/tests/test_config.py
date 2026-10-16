from __future__ import annotations

import json
from pathlib import Path

import pytest
from voice_broker.config import (
    DecisionsProvider,
    Device,
    History,
    HomeAssistantAudio,
    JevProvider,
    Routing,
    RoutingShadow,
    load,
)

ROOM = Device("room-assistant", "192.168.1.54", "Room", "esphome.home_assistant_voice_0914cc_start_conversation")


def write_config(tmp_path: Path, **live: str) -> Path:
    for name in ("device-token", "openai-api-key", "openclaw-secret", "ha-token"):
        (tmp_path / name).write_text("secret\n")
    path = tmp_path / "config.json"
    path.write_text(
        json.dumps(
            {
                "listen_host": "127.0.0.1",
                "listen_port": 0,
                "device_token_file": str(tmp_path / "device-token"),
                "openai_api_key_file": str(tmp_path / "openai-api-key"),
                "devices": [
                    {"name": ROOM.name, "address": ROOM.address, "area": ROOM.area, "call_action": ROOM.call_action}
                ],
                "calls": {
                    "socket": str(tmp_path / "call.sock"),
                    "home_assistant_url": "http://ha.test",
                    "home_assistant_token_file": str(tmp_path / "ha-token"),
                },
                "live": {"model": "gpt-live-1", "voice": "marin", "instructions": "Speak briefly.", **live},
                "openclaw": {
                    "url": "http://openclaw.test",
                    "token_file": str(tmp_path / "openclaw-secret"),
                    "session_key": "agent:main:main",
                    "instructions": "",
                    "history": {"max_messages": 40, "max_age_s": 86400, "max_chars": 8000},
                },
                "idle_timeout_s": 1,
                "max_conversation_s": 30,
            }
        )
    )
    return path


def test_the_speakers_and_the_calls_are_read(tmp_path: Path) -> None:
    config = load(write_config(tmp_path))
    assert config.devices == [ROOM]
    assert config.calls.socket == tmp_path / "call.sock"
    assert config.calls.home_assistant_url == "http://ha.test"
    assert config.calls.home_assistant_token == "secret"


def test_the_agents_session_and_history_bounds_are_read(tmp_path: Path) -> None:
    openclaw = load(write_config(tmp_path)).openclaw
    assert openclaw.session_key == "agent:main:main"
    assert openclaw.history == History(max_messages=40, max_age_s=86400.0, max_chars=8000)


def test_identity_leads_the_instructions(tmp_path: Path) -> None:
    identity = tmp_path / "identity"
    identity.write_text("- **Name:** Calcifer\n")
    instructions = load(write_config(tmp_path, identity_file=str(identity))).live.instructions
    lead, rest = instructions.split("\n", 1)
    assert lead.startswith("Who you are")
    assert rest == "- **Name:** Calcifer\n\nSpeak briefly."


def test_empty_identity_keeps_the_instructions(tmp_path: Path) -> None:
    identity = tmp_path / "identity"
    identity.write_text("\n")
    assert load(write_config(tmp_path, identity_file=str(identity))).live.instructions == "Speak briefly."


def test_no_identity_file_keeps_the_instructions(tmp_path: Path) -> None:
    assert load(write_config(tmp_path)).live.instructions == "Speak briefly."


ROUTING = {
    "model": "gpt-6-luna",
    "timeout_s": 4,
    "pipeline": "01jmq3hbakt5r0e136vd886hy9",
    "pending_question_s": 60,
    "settle_s": 0.35,
}


def with_routing(path: Path, routing: dict | None, device_id: str | None = "9290a2568e3df21ba0fd2d663249c0ca") -> Path:
    raw = json.loads(path.read_text())
    if routing is not None:
        raw["routing"] = routing
    if device_id is not None:
        raw["devices"][0]["home_assistant_device_id"] = device_id
    path.write_text(json.dumps(raw))
    return path


def test_no_routing_keeps_every_request_with_the_agent(tmp_path: Path) -> None:
    config = load(write_config(tmp_path))
    assert config.routing is None and config.devices[0].home_assistant_device_id is None


def test_routing_and_the_speakers_home_assistant_device_are_read(tmp_path: Path) -> None:
    config = load(with_routing(write_config(tmp_path), ROUTING))
    assert config.routing == Routing(DecisionsProvider("gpt-6-luna"), 4.0, "01jmq3hbakt5r0e136vd886hy9", 60.0, 0.35)
    assert config.devices[0].home_assistant_device_id == "9290a2568e3df21ba0fd2d663249c0ca"


def test_the_diagnostic_routing_limit_is_accepted(tmp_path: Path) -> None:
    config = load(with_routing(write_config(tmp_path), {**ROUTING, "timeout_s": 30}))
    assert config.routing is not None and config.routing.timeout_s == 30.0


def test_routing_needs_every_speakers_home_assistant_device(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="room-assistant"):
        load(with_routing(write_config(tmp_path), ROUTING, device_id=None))


@pytest.mark.parametrize(
    "change",
    [
        {"pending_question_s": 300},
        {"pending_question_s": 0},
        {"timeout_s": 0},
        # The limit that ran out on a cold request on 2026-10-16.
        {"timeout_s": 1.5},
        {"timeout_s": 2.9},
        {"timeout_s": 30.5},
        {"settle_s": 0},
        {"settle_s": 1.5},
        {"pipeline": ""},
        {"model": ""},
    ],
)
def test_routing_bounds_are_checked(tmp_path: Path, change: dict) -> None:
    with pytest.raises(ValueError):
        load(with_routing(write_config(tmp_path), {**ROUTING, **change}))


# -- the routing provider ----------------------------------------------------


def jev_routing(tmp_path: Path, key: str = "sk-or-v1-secret\n") -> dict:
    (tmp_path / "openrouter-api-key").write_text(key)
    return {
        **ROUTING,
        "provider": "jev",
        "model": "typesafe/jev-1.13",
        "api_key_file": str(tmp_path / "openrouter-api-key"),
    }


def test_a_config_without_a_provider_still_routes_with_decisions(tmp_path: Path) -> None:
    # Configs from before the choice existed name only Decisions' model.
    config = load(with_routing(write_config(tmp_path), ROUTING))
    assert config.routing is not None and config.routing.provider == DecisionsProvider("gpt-6-luna")


def test_decisions_can_be_named(tmp_path: Path) -> None:
    config = load(with_routing(write_config(tmp_path), {**ROUTING, "provider": "decisions"}))
    assert config.routing is not None and config.routing.provider == DecisionsProvider("gpt-6-luna")


def test_jev_reads_its_openrouter_key_and_keeps_it_out_of_the_repr(tmp_path: Path) -> None:
    config = load(with_routing(write_config(tmp_path), jev_routing(tmp_path)))
    assert config.routing is not None
    assert config.routing.provider == JevProvider("typesafe/jev-1.13", "sk-or-v1-secret")
    assert "sk-or-v1-secret" not in repr(config.routing)
    assert config.routing.timeout_s == 4.0 and config.routing.pipeline == ROUTING["pipeline"]


@pytest.mark.parametrize(
    ("change", "message"),
    [
        ({"provider": "chat"}, "must be one of decisions, jev"),
        ({"provider": "Jev"}, "must be one of decisions, jev"),
        ({"provider": None}, "must be one of decisions, jev"),
        ({"api_key_file": None}, "needs api_key_file"),
        ({"model": ""}, "needs a model"),
    ],
)
def test_a_wrong_jev_or_unknown_provider_is_refused(tmp_path: Path, change: dict, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        load(with_routing(write_config(tmp_path), {**jev_routing(tmp_path), **change}))


def test_an_empty_openrouter_key_is_refused(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="empty"):
        load(with_routing(write_config(tmp_path), jev_routing(tmp_path, key="\n")))


def test_a_missing_openrouter_key_file_stops_the_broker(tmp_path: Path) -> None:
    routing = {**jev_routing(tmp_path), "api_key_file": str(tmp_path / "missing")}
    with pytest.raises(FileNotFoundError):
        load(with_routing(write_config(tmp_path), routing))


def test_decisions_takes_no_openrouter_key(tmp_path: Path) -> None:
    # Decisions runs on the broker's OpenAI key; a stray key file is a config mistake.
    with pytest.raises(ValueError, match="api_key_file is for jev"):
        load(with_routing(write_config(tmp_path), {**jev_routing(tmp_path), "provider": "decisions"}))


# -- the voice agent's sessions ------------------------------------------------


def test_the_voice_agent_reads_history_from_another_session_and_observes_in_its_own(tmp_path: Path) -> None:
    path = write_config(tmp_path)
    raw = json.loads(path.read_text())
    raw["openclaw"] |= {
        "agent": "voice",
        "session_key": "agent:voice:main",
        "history_session_key": "agent:main:main",
        "observer_session_key": "agent:voice:observer",
    }
    path.write_text(json.dumps(raw))
    openclaw = load(path).openclaw
    assert (openclaw.agent, openclaw.session_key, openclaw.history_session_key, openclaw.observer_session_key) == (
        "voice",
        "agent:voice:main",
        "agent:main:main",
        "agent:voice:observer",
    )


def test_unset_the_agents_sessions_are_the_consult_session_and_none_is_named(tmp_path: Path) -> None:
    openclaw = load(write_config(tmp_path)).openclaw
    # Unset: history comes from the consult session, nothing is observed, and no agent is named (gated, as deployed).
    assert openclaw.history_session_key is None and openclaw.observer_session_key is None
    assert openclaw.agent is None


@pytest.mark.parametrize(
    "keys",
    [
        {"session_key": "agent:main:main"},
        {"session_key": "agent:voice:main", "observer_session_key": "agent:main:observer"},
    ],
)
def test_a_session_of_another_agent_than_the_named_one_is_refused(tmp_path: Path, keys: dict) -> None:
    path = write_config(tmp_path)
    raw = json.loads(path.read_text())
    raw["openclaw"] |= {"agent": "voice", **keys}
    path.write_text(json.dumps(raw))
    with pytest.raises(ValueError, match="is not agent 'voice'"):
        load(path)


# -- parallel: Home Assistant hears the audio ------------------------------------

HOME = {
    "pipeline": "Voice broker home",
    "read_only_tools": ["GetLiveContext", "GetDateTime"],
    "non_home_tools": ["ask_gpt"],
}
SHADOW = {"model": "gpt-6-luna", "timeout_s": 4}


def with_raw(path: Path, device_id: str | None = "9290a2568e3df21ba0fd2d663249c0ca", **sections: object) -> Path:
    raw = json.loads(path.read_text())
    raw.update(sections)
    if device_id is not None:
        raw["devices"][0]["home_assistant_device_id"] = device_id
    path.write_text(json.dumps(raw))
    return path


def test_home_assistant_listening_and_the_speakers_device_are_read(tmp_path: Path) -> None:
    config = load(with_raw(write_config(tmp_path), home_assistant=HOME))
    assert config.home_assistant == HomeAssistantAudio(
        "Voice broker home", frozenset({"GetLiveContext", "GetDateTime"}), frozenset({"ask_gpt"})
    )
    assert config.devices[0].home_assistant_device_id == "9290a2568e3df21ba0fd2d663249c0ca"
    # Listening on its own gates nothing and makes no classifier request.
    assert config.routing is None and config.home_assistant.shadow is None


def test_without_either_mode_home_assistant_neither_listens_nor_is_routed_to(tmp_path: Path) -> None:
    config = load(write_config(tmp_path))
    assert config.home_assistant is None and config.routing is None


def test_a_decisions_shadow_is_read(tmp_path: Path) -> None:
    config = load(with_raw(write_config(tmp_path), home_assistant={**HOME, "shadow": SHADOW}))
    assert config.home_assistant is not None
    assert config.home_assistant.shadow == RoutingShadow(DecisionsProvider("gpt-6-luna"), 4.0)


def test_a_jev_shadow_reads_its_key_through_the_same_provider_config(tmp_path: Path) -> None:
    shadow = {k: v for k, v in jev_routing(tmp_path).items() if k in ("provider", "model", "api_key_file", "timeout_s")}
    config = load(with_raw(write_config(tmp_path), home_assistant={**HOME, "shadow": shadow}))
    assert config.home_assistant is not None
    assert config.home_assistant.shadow == RoutingShadow(JevProvider("typesafe/jev-1.13", "sk-or-v1-secret"), 4.0)
    assert "sk-or-v1-secret" not in repr(config)


def test_a_jev_shadow_without_a_key_is_refused_with_its_own_name(tmp_path: Path) -> None:
    shadow = {"provider": "jev", "model": "typesafe/jev-1.13", "timeout_s": 4}
    with pytest.raises(ValueError, match=r"^home_assistant\.shadow\.provider jev needs api_key_file"):
        load(with_raw(write_config(tmp_path), home_assistant={**HOME, "shadow": shadow}))


def test_home_assistant_needs_every_speakers_device(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="room-assistant"):
        load(with_raw(write_config(tmp_path), device_id=None, home_assistant=HOME))


def test_gated_and_parallel_together_are_refused(tmp_path: Path) -> None:
    # Home Assistant would act twice on one request: on the gated text, and on the audio.
    with pytest.raises(ValueError, match="exclusive"):
        load(with_raw(write_config(tmp_path), routing=ROUTING, home_assistant=HOME))


def test_the_undeployed_top_level_shadow_is_refused(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="home_assistant.shadow now"):
        load(with_raw(write_config(tmp_path), home_assistant=HOME, decisions_shadow=SHADOW))


@pytest.mark.parametrize(
    "home",
    [
        {**HOME, "pipeline": ""},
        # A tool can't be both: the evidence would be ambiguous.
        {**HOME, "non_home_tools": ["GetLiveContext"]},
    ],
)
def test_home_assistant_settings_are_checked(tmp_path: Path, home: dict) -> None:
    with pytest.raises(ValueError):
        load(with_raw(write_config(tmp_path), home_assistant=home))


@pytest.mark.parametrize("change", [{"timeout_s": 2.9}, {"timeout_s": 30.5}, {"model": ""}, {"provider": "chat"}])
def test_shadow_bounds_are_checked(tmp_path: Path, change: dict) -> None:
    with pytest.raises(ValueError):
        load(with_raw(write_config(tmp_path), home_assistant={**HOME, "shadow": {**SHADOW, **change}}))
