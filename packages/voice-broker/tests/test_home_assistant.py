"""Home Assistant's conversation agent over a scripted Assist WebSocket."""

from __future__ import annotations

import asyncio
import json
from contextlib import asynccontextmanager

import pytest
from voice_broker.home_assistant import HomeAssistant, HomeAssistantFailed, HomeReply

PIPELINE = "01jmq3hbakt5r0e136vd886hy9"
KITCHEN = "70f12d431cf502faeefdc782b45c0719"


class Socket:
    def __init__(self, replies: list[dict], hang: bool = False) -> None:
        self.replies = [json.dumps({"type": "auth_required"}), *map(json.dumps, replies)]
        self.sent: list[dict] = []
        self.hang = hang

    async def recv(self) -> str:
        return self.replies.pop(0)

    async def send(self, message: str) -> None:
        self.sent.append(json.loads(message))

    def __aiter__(self):
        return self

    async def __anext__(self) -> str:
        if not self.replies:
            if self.hang:
                await asyncio.Event().wait()
            raise StopAsyncIteration
        return self.replies.pop(0)


def connector(socket: Socket, urls: list[str]):
    @asynccontextmanager
    async def connect(url: str, **kwargs):
        urls.append(url)
        yield socket

    return connect


def event(kind: str, data: dict | None = None) -> dict:
    return {"id": 1, "type": "event", "event": {"type": kind, "data": data or {}}}


def run_events(speech: str, response_type: str = "action_done", continues: bool = False, cid: str = "01JQ"):
    return [
        {"type": "auth_ok"},
        {"id": 1, "type": "result", "success": True},
        event("run-start"),
        event("intent-start"),
        event(
            "intent-end",
            {
                "intent_output": {
                    "response": {"response_type": response_type, "speech": {"plain": {"speech": speech}}},
                    "conversation_id": cid,
                    "continue_conversation": continues,
                }
            },
        ),
        event("run-end"),
    ]


def converse(socket: Socket, text: str = "Turn on the light.", conversation_id: str | None = None):
    urls: list[str] = []
    home = HomeAssistant("https://ha.test:8123", "ha-token", PIPELINE, KITCHEN, connector(socket, urls))
    reply = asyncio.run(home.converse(text, conversation_id))
    return reply, urls


def test_a_question_comes_back_with_its_conversation():
    socket = Socket(run_events("Which light?", "query_answer", continues=True))

    reply, urls = converse(socket)

    assert reply == HomeReply("Which light?", "01JQ", continue_conversation=True)
    assert urls == ["wss://ha.test:8123/api/websocket"]
    auth, run = socket.sent
    assert auth == {"type": "auth", "access_token": "ha-token"}
    assert run == {
        "id": 1,
        "type": "assist_pipeline/run",
        "pipeline": PIPELINE,
        "start_stage": "intent",
        "end_stage": "intent",
        "input": {"text": "Turn on the light."},
        "device_id": KITCHEN,
        "timeout": 19.0,
    }


def test_an_answer_continues_the_given_conversation():
    socket = Socket(run_events("The kitchen light is on."))

    reply, _ = converse(socket, "Kitchen.", "01JQ")

    assert socket.sent[1]["conversation_id"] == "01JQ"
    assert reply == HomeReply("The kitchen light is on.", "01JQ", continue_conversation=False)


def test_an_error_response_never_continues():
    reply, _ = converse(Socket(run_events("", "error", continues=True)))

    assert reply.speech and not reply.continue_conversation


def test_a_question_without_a_conversation_id_cannot_be_continued():
    reply, _ = converse(Socket(run_events("Which one?", "query_answer", continues=True, cid="")))

    assert reply.conversation_id is None and not reply.continue_conversation


@pytest.mark.parametrize(
    "replies",
    [
        [{"type": "auth_invalid"}],
        [{"type": "auth_ok"}, {"id": 1, "type": "result", "success": False}],
        [{"type": "auth_ok"}, event("error", {"code": "intent-failed"})],
        [{"type": "auth_ok"}, event("run-end")],
        # disconnected mid-run
        [{"type": "auth_ok"}, event("run-start")],
        [{"type": "auth_ok"}, "not json"],
        # JSON, but not the objects the API sends
        [{"type": "auth_ok"}, "[]"],
        [{"type": "auth_ok"}, {"id": 1, "type": "event", "event": "x"}],
        [{"type": "auth_ok"}, event("intent-end", {"intent_output": "x"}), event("run-end")],
    ],
)
def test_failures_raise_and_are_not_retried(replies):
    socket = Socket([])
    socket.replies += [r if isinstance(r, str) else json.dumps(r) for r in replies]

    with pytest.raises(HomeAssistantFailed):
        converse(socket)

    assert [m.get("type") for m in socket.sent].count("assist_pipeline/run") <= 1


def test_a_run_that_hangs_times_out(monkeypatch):
    monkeypatch.setattr("voice_broker.home_assistant._TIMEOUT_S", 0.05)
    socket = Socket([{"type": "auth_ok"}, event("run-start")], hang=True)

    with pytest.raises(HomeAssistantFailed):
        converse(socket)


def test_an_unreachable_home_assistant_fails():
    @asynccontextmanager
    async def refuse(url: str, **kwargs):
        raise OSError("connection refused")
        yield

    home = HomeAssistant("http://ha.test:8123", "ha-token", PIPELINE, KITCHEN, refuse)

    with pytest.raises(HomeAssistantFailed):
        asyncio.run(home.converse("Turn on the light.", None))
