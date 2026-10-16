import asyncio

import pytest

from voice_broker.dispatch import Dispatcher, agent_task
from voice_broker.openclaw import ConsultFailed
from voice_broker.routing import NaiveRouter, RouteDecision, RouteRequest


def request(text, context=()):
    return RouteRequest(text, context, "Room", "room-assistant", "voice-1")


@pytest.mark.parametrize(
    "text,route",
    [
        ("Turn off the lights.", "ha"),
        ("Вимкни світло в кімнаті.", "ha"),
        ("Activate the Sleep scene.", "ha"),
        ("Увімкни режим сну.", "ha"),
        ("Write Python code.", "openclaw"),
        ("Напиши код для бота.", "openclaw"),
        ("What's the weather in Kyiv?", "openclaw"),
        ("А завтра?", "clarify"),
        ("Do it.", "clarify"),
        ("Turn off.", "clarify"),
        ("Turn off the lights and", "clarify"),
        ("Turn off the lights and write Python code.", "clarify"),
    ],
)
def test_naive_baseline(text, route):
    decision = asyncio.run(NaiveRouter().route(request(text)))
    assert decision.route == route and decision.elapsed_ms >= 0


@pytest.mark.parametrize("route", ["ha", "openclaw", "clarify"])
def test_exactly_one_backend(route):
    calls = []

    class Router:
        async def route(self, req):
            return RouteDecision(route)

    async def home(req):
        calls.append("ha")
        return "Done."

    async def agent(req):
        calls.append("openclaw")
        return "Done."

    asyncio.run(Dispatcher(Router(), home, agent).consult(request("Test.")))
    assert calls == ([] if route == "clarify" else [route])


def test_uncertain_action_does_not_fallback():
    async def home(req):
        raise ConsultFailed("timeout after action")

    async def agent(req):
        raise AssertionError("must never execute fallback")

    with pytest.raises(ConsultFailed):
        asyncio.run(Dispatcher(NaiveRouter(), home, agent).consult(request("Turn off lights.")))


def test_correction_during_classification_blocks_execution():
    async def backend(req):
        raise AssertionError("stale request must not execute")

    result = asyncio.run(Dispatcher(NaiveRouter(), backend, backend, lambda _: False).consult(request("Lights off.")))
    assert "changed" in result


def test_full_context_and_latest_request_are_distinct():
    task = agent_task(request("And tomorrow?", (("user", "Weather in Kyiv?"), ("assistant", "Sunny."))))
    assert "Weather in Kyiv?" in task and "And tomorrow?" in task and "voice-1" in task and "Room" in task
