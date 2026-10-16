import asyncio
import json
from contextlib import asynccontextmanager

import pytest

from voice_broker.home_assistant import HomeAssistant
from voice_broker.openclaw import ConsultFailed
from voice_broker.routing import RouteRequest


class Socket:
    def __init__(self, events):
        self.events = iter(events)
        self.sent = []

    async def recv(self):
        return json.dumps(next(self.events))

    async def send(self, raw):
        self.sent.append(json.loads(raw))

    def __aiter__(self):
        return self

    async def __anext__(self):
        try:
            return json.dumps(next(self.events))
        except StopIteration:
            raise StopAsyncIteration


def event(kind, data=None):
    return {"id": 1, "type": "event", "event": {"type": kind, "data": data or {}}}


def test_remote_pipeline_intent_only_and_conversation_continuity():
    sockets = []

    @asynccontextmanager
    async def connect(*args, **kwargs):
        ws = Socket(
            [
                {"type": "auth_required"},
                {"type": "auth_ok"},
                {"id": 1, "type": "result", "success": True},
                event(
                    "intent-end",
                    {
                        "intent_output": {
                            "conversation_id": "ha-conv",
                            "response": {"speech": {"plain": {"speech": "It is 22 degrees."}}},
                        }
                    },
                ),
                event("run-end"),
            ]
        )
        sockets.append(ws)
        yield ws

    home = HomeAssistant("http://ha.test:8123", "secret", "remote-pipeline", "device-room", connect)

    async def run():
        req = RouteRequest("What is the temperature?", (), "Room", "speaker", "voice-1")
        assert await home.consult(req) == "It is 22 degrees."
        assert await home.consult(req) == "It is 22 degrees."

    asyncio.run(run())
    first, second = [ws.sent[1] for ws in sockets]
    assert first["pipeline"] == "remote-pipeline" and first["device_id"] == "device-room"
    assert first["start_stage"] == first["end_stage"] == "intent"
    assert first["input"] == {"text": "What is the temperature?"}
    assert "conversation_id" not in first and second["conversation_id"] == "ha-conv"


@pytest.mark.parametrize(
    "events", [[], [event("error")], [event("run-end")], [{"id": 1, "type": "result", "success": False}]]
)
def test_failures_are_never_retried(events):
    sockets = []

    @asynccontextmanager
    async def connect(*args, **kwargs):
        ws = Socket([{"type": "auth_required"}, {"type": "auth_ok"}] + events)
        sockets.append(ws)
        yield ws

    home = HomeAssistant("http://ha.test", "secret", "remote", "device", connect)
    with pytest.raises(ConsultFailed):
        asyncio.run(home.consult(RouteRequest("Lights off.", (), "Room", "speaker", "v1")))
    assert len(sockets) == 1 and len(sockets[0].sent) == 2


def test_correction_during_auth_does_not_send_action():
    current = True
    sockets = []

    class DelayedAuth(Socket):
        async def recv(self):
            nonlocal current
            result = await super().recv()
            if json.loads(result).get("type") == "auth_ok":
                current = False
            return result

    @asynccontextmanager
    async def connect(*args, **kwargs):
        ws = DelayedAuth([{"type": "auth_required"}, {"type": "auth_ok"}])
        sockets.append(ws)
        yield ws

    home = HomeAssistant("http://ha.test", "secret", "remote", "device", connect, is_current=lambda _: current)
    result = asyncio.run(home.consult(RouteRequest("Lights off.", (), "Room", "d", "v")))
    assert "changed" in result and len(sockets[0].sent) == 1


def test_cross_backend_followup_does_not_use_missing_ha_context():
    @asynccontextmanager
    async def connect(*args, **kwargs):
        raise AssertionError("must clarify before connecting")
        yield

    home = HomeAssistant("http://ha.test", "secret", "remote", "device", connect)
    result = asyncio.run(home.consult(RouteRequest("Dim them.", (("user", "Lights are on."),), "Room", "d", "v")))
    assert "No action" in result
