"""Which mode a conversation gets from the broker's config: consult, gated or parallel, at a wake word or a call."""

from __future__ import annotations

from dataclasses import replace

import pytest
from voice_broker.__main__ import Broker
from voice_broker.config import (
    DecisionsProvider,
    Device,
    HomeAssistantAudio,
    JevProvider,
    Routing,
    RoutingShadow,
)
from voice_broker.live import Parallel, Routed
from voice_broker.routing import DecisionsRouter, JevRouter

ROOM = Device(
    "room-assistant", "192.168.1.54", "Room", "esphome.x_start_conversation", "9290a2568e3df21ba0fd2d663249c0ca"
)
GATED = Routing(JevProvider("typesafe/jev-1.13", "sk-or-v1-secret"), 30.0, "01jmq3hbakt5r0e136vd886hy9", 60.0, 0.35)
HOME = HomeAssistantAudio("Voice broker home", frozenset({"GetLiveContext"}), frozenset({"ask_gpt"}))
WAKE, CALL = None, "The washing machine is done."


def broker(make_config, **mode) -> Broker:
    return Broker(make_config(devices=[ROOM], **mode))


def state(b: Broker):
    return b._devices[ROOM.address]


@pytest.mark.parametrize("opening", [WAKE, CALL])
def test_without_a_mode_every_conversation_only_consults(make_config, opening) -> None:
    b = broker(make_config)
    assert b._mode(state(b), opening) is None
    assert b._router is None


def test_gated_routes_a_woken_conversation_with_the_configured_classifier(make_config) -> None:
    b = broker(make_config, routing=GATED)
    mode = b._mode(state(b), WAKE)
    assert isinstance(mode, Routed)
    assert isinstance(b._router, JevRouter) and b._router.label == "jev typesafe/jev-1.13"
    # The gate is the router itself: nothing else picks a backend.
    assert mode.route == b._router.route
    assert (mode.pending_question_s, mode.settle_s) == (60.0, 0.35)


def test_gated_leaves_a_call_to_the_agent_that_opened_it(make_config) -> None:
    # A call answers the agent, so the reply is the agent's whatever it says, as before parallel mode.
    b = broker(make_config, routing=GATED)
    assert b._mode(state(b), CALL) is None


@pytest.mark.parametrize("opening", [WAKE, CALL])
def test_parallel_listens_in_every_conversation_and_classifies_nothing_unless_shadowing(make_config, opening) -> None:
    # In a call too: Home Assistant alone acts on the home, whoever opened the conversation.
    b = broker(make_config, home_assistant=HOME)
    mode = b._mode(state(b), opening)
    assert isinstance(mode, Parallel)
    assert mode.shadow is None and b._router is None
    # No observer session configured: no observation.
    assert mode.observe is None


def test_a_parallel_shadow_takes_the_same_router_factory_and_never_gates(make_config) -> None:
    shadow = RoutingShadow(JevProvider("typesafe/jev-1.13", "sk-or-v1-secret"), 4.0)
    b = broker(make_config, home_assistant=replace(HOME, shadow=shadow))
    mode = b._mode(state(b), WAKE)
    assert isinstance(mode, Parallel) and isinstance(b._router, JevRouter)
    assert mode.shadow == b._router.route


def test_a_decisions_shadow_shares_the_brokers_openai_client(make_config) -> None:
    b = broker(make_config, home_assistant=replace(HOME, shadow=RoutingShadow(DecisionsProvider("gpt-6-luna"), 4.0)))
    assert isinstance(b._router, DecisionsRouter) and b._router.label == "decisions gpt-6-luna"


def test_parallel_observes_through_the_voice_agent_only_when_its_session_is_set(make_config) -> None:
    config = make_config(devices=[ROOM], home_assistant=HOME)
    config = replace(config, openclaw=replace(config.openclaw, observer_session_key="agent:voice:observer"))
    b = Broker(config)
    mode = b._mode(state(b), WAKE)
    assert isinstance(mode, Parallel) and mode.observe == b._openclaw.observe


def test_a_conversation_runs_home_assistant_as_its_own_speaker(make_config) -> None:
    b = broker(make_config, home_assistant=HOME)
    mode = b._mode(state(b), WAKE)
    assert isinstance(mode, Parallel)
    # The ESPHome Voice PE's own device, so Home Assistant resolves its area (Room) by it.
    assert mode.home._device_id == ROOM.home_assistant_device_id
    # Runs of every conversation at this speaker take turns.
    assert mode.home._lock is state(b).home_runs


def test_every_conversation_gets_consults_of_its_own(make_config) -> None:
    # An overflow session is a conversation's alone: never shared with the speaker's next one, or another speaker's.
    b = broker(make_config)
    first, second = b._consults(ROOM), b._consults(ROOM)
    assert first is not second
    assert first.id != second.id
    assert first.id.startswith("room-assistant-") and second.id.startswith("room-assistant-")
    assert first.session_key is None
