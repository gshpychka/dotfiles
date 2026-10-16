"""The agent client against a mocked gateway."""

from __future__ import annotations

import asyncio
import json
import time
from collections.abc import Awaitable, Callable

import httpx2
import pytest
from voice_broker.config import History
from voice_broker.config import OpenClaw as OpenClawConfig
from voice_broker.openclaw import ConsultFailed, HistoryUnavailable, OpenClaw, Turn

Handler = Callable[[httpx2.Request], httpx2.Response]


def config(model: str | None = None, history: History | None = None) -> OpenClawConfig:
    return OpenClawConfig(
        url="http://openclaw.test",
        token="gateway-secret",
        session_key="agent:main:main",
        instructions="Be brief.",
        model=model,
        history=history or History(max_messages=40, max_age_s=3600, max_chars=8000),
    )


def call[T](handler: Handler, use: Callable[[OpenClaw], Awaitable[T]], **overrides) -> T:
    async def main() -> T:
        http_client = httpx2.AsyncClient(transport=httpx2.MockTransport(handler))
        client = OpenClaw(config(**overrides), http_client=http_client)
        try:
            return await use(client)
        finally:
            await client.aclose()

    return asyncio.run(main())


def consult(handler: Handler, model: str | None = None) -> str:
    return call(handler, lambda client: client.consult("Turn off the lights."), model=model)


def recent(handler: Handler, history: History | None = None) -> list[Turn]:
    return call(handler, lambda client: client.recent(), history=history)


def answer(text: str, status: str = "completed") -> dict:
    return {
        "id": "resp_1",
        "object": "response",
        "status": status,
        "output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": text}]}],
    }


def text(value: str) -> dict:
    return {"type": "text", "text": value}


def message(role: str, *content: dict, age_s: float | None = 0.0) -> dict:
    """A history message as the gateway renders it; `age_s` None leaves the timestamp out."""
    fields = {"role": role, "content": list(content)}
    if age_s is not None:
        fields["timestamp"] = (time.time() - age_s) * 1000
    return fields


def history_of(*messages: dict) -> Handler:
    def handler(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(200, json={"sessionKey": "agent:main:main", "messages": list(messages)})

    return handler


# -- consults ---------------------------------------------------------------


def test_a_consult_is_one_turn_of_the_agents_session():
    requests: list[httpx2.Request] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        requests.append(request)
        return httpx2.Response(200, json=answer("The lights are off."))

    assert consult(handler) == "The lights are off."
    (request,) = requests
    assert str(request.url) == "http://openclaw.test/v1/responses"
    assert request.headers["authorization"] == "Bearer gateway-secret"
    assert request.headers["x-openclaw-session-key"] == "agent:main:main"
    # The agent keeps its own model unless one is configured.
    assert "x-openclaw-model" not in request.headers
    assert json.loads(request.content) == {
        "model": "openclaw",
        "input": "Turn off the lights.",
        "instructions": "Be brief.",
    }


def test_a_configured_model_overrides_the_agents():
    def handler(request: httpx2.Request) -> httpx2.Response:
        assert request.headers["x-openclaw-model"] == "openai/gpt-6-luna"
        return httpx2.Response(200, json=answer("Done."))

    assert consult(handler, model="openai/gpt-6-luna") == "Done."


def test_a_failed_turn_fails_once_without_a_retry():
    requests: list[httpx2.Request] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        requests.append(request)
        return httpx2.Response(
            500, json={"status": "failed", "error": {"code": "api_error", "message": "internal error"}}
        )

    with pytest.raises(ConsultFailed, match="internal error"):
        consult(handler)
    assert len(requests) == 1


def test_an_unreachable_gateway_fails():
    def handler(request: httpx2.Request) -> httpx2.Response:
        raise httpx2.ConnectError("connection refused", request=request)

    with pytest.raises(ConsultFailed, match="Connection"):
        consult(handler)


def test_a_turn_without_text_fails():
    def handler(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(200, json=answer("   "))

    with pytest.raises(ConsultFailed):
        consult(handler)


# -- the recent conversation --------------------------------------------------


def test_the_recent_conversation_is_the_agents_sessions_newest_messages():
    requests: list[httpx2.Request] = []
    history = history_of(message("user", text("Are the lights on?")), message("assistant", text("They are.")))

    def handler(request: httpx2.Request) -> httpx2.Response:
        requests.append(request)
        return history(request)

    assert recent(handler) == [("user", "Are the lights on?"), ("assistant", "They are.")]
    (request,) = requests
    assert str(request.url) == "http://openclaw.test/sessions/agent%3Amain%3Amain/history?limit=40"
    assert request.headers["authorization"] == "Bearer gateway-secret"


def test_only_what_was_said_is_kept():
    handler = history_of(
        message("user", text("Hi")),
        message("assistant", {"type": "thinking", "thinking": "..."}, {"type": "toolCall", "id": "c1", "name": "exec"}),
        message("toolResult", text("exit 0")),
        message("assistant", text("Done."), text(" Anything else? ")),
        message("assistant", text("   ")),
        message("user", text("")),
    )

    assert recent(handler) == [("user", "Hi"), ("assistant", "Done.\nAnything else?")]


def test_old_messages_are_left_out():
    handler = history_of(
        message("user", text("yesterday"), age_s=2 * 3600),
        message("assistant", text("undated"), age_s=None),
        message("user", text("just now"), age_s=60),
    )

    assert recent(handler) == [("assistant", "undated"), ("user", "just now")]


def test_the_newest_messages_fill_the_text_budget():
    handler = history_of(
        message("user", text("aaaa")),
        message("assistant", text("bbbbbbbb")),
        message("user", text("cccc")),
    )

    assert recent(handler, History(max_messages=40, max_age_s=3600, max_chars=10)) == [("user", "cccc")]
    assert recent(handler, History(max_messages=40, max_age_s=3600, max_chars=3)) == []


def test_an_unreadable_conversation_is_unavailable():
    def missing(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(404, json={"ok": False, "error": {"type": "not_found"}})

    def unreachable(request: httpx2.Request) -> httpx2.Response:
        raise httpx2.ConnectError("connection refused", request=request)

    def malformed(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(200, json={"items": []})

    def not_json(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(200, text="<html>")

    for handler in (missing, unreachable, malformed, not_json):
        with pytest.raises(HistoryUnavailable):
            recent(handler)


# -- the voice agent's sessions and the observer -----------------------------

VOICE = {
    "agent": "voice",
    "session_key": "agent:voice:main",
    "history_session_key": "agent:main:main",
    "observer_session_key": "agent:voice:observer",
}


def voice_call[T](handler: Handler, use: Callable[[OpenClaw], Awaitable[T]]) -> T:
    async def main() -> T:
        base = config()
        voice = OpenClawConfig(**{**{f: getattr(base, f) for f in base.__slots__}, **VOICE})
        client = OpenClaw(voice, http_client=httpx2.AsyncClient(transport=httpx2.MockTransport(handler)))
        try:
            return await use(client)
        finally:
            await client.aclose()

    return asyncio.run(main())


def test_consults_run_as_the_voice_agent_and_history_still_comes_from_the_main_session():
    seen: list[tuple[str, str | None]] = []
    agents: list[str | None] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        seen.append((request.url.path, request.headers.get("x-openclaw-session-key")))
        agents.append(request.headers.get("x-openclaw-agent-id"))
        if request.url.path.endswith("/history"):
            return httpx2.Response(200, json={"messages": [message("user", text("hi"))]})
        return httpx2.Response(200, json=answer("Rain after four."))

    async def use(client: OpenClaw) -> tuple[str, list[Turn]]:
        return await client.consult("Will it rain?"), await client.recent()

    assert voice_call(handler, use) == ("Rain after four.", [("user", "hi")])
    # The session key picks the agent, and with it the tools; history is read from main's transcript.
    assert seen[0] == ("/v1/responses", "agent:voice:main")
    # Named too: with two agents the gateway has no default to fall back on for an unnamed request.
    assert agents[0] == "voice"
    assert seen[1][0] == "/sessions/agent:main:main/history"


def verdict(arguments: dict | str, name: str = "home_verdict") -> dict:
    return {
        "id": "resp_2",
        "object": "response",
        "status": "completed",
        "output": [
            {
                "type": "function_call",
                "id": "fc_1",
                "call_id": "call_1",
                "name": name,
                "arguments": arguments if isinstance(arguments, str) else json.dumps(arguments),
            }
        ],
    }


def observe(response: dict) -> tuple[str | None, dict, dict]:
    sent: list[tuple[dict, dict]] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        sent.append((json.loads(request.content), dict(request.headers)))
        return httpx2.Response(200, json=response)

    result = voice_call(handler, lambda client: client.observe("evidence"))
    ((body, headers),) = sent
    return result, body, headers


def test_the_observer_answers_through_one_required_function_call_in_its_own_session():
    result, body, headers = observe(verdict({"matches": True}))
    assert result is None
    assert headers["x-openclaw-session-key"] == "agent:voice:observer"
    assert headers["x-openclaw-agent-id"] == "voice"
    assert body["tool_choice"] == {"type": "function", "name": "home_verdict"}
    assert [t["name"] for t in body["tools"]] == ["home_verdict"]
    assert "never change anything" in body["instructions"]


def test_a_mismatch_is_the_sentence_to_tell():
    result, _, _ = observe(verdict({"matches": False, "discrepancy": "The hallway light is on, not the kitchen's."}))
    assert result == "The hallway light is on, not the kitchen's."


@pytest.mark.parametrize(
    "response",
    [
        verdict({"matches": False}),
        verdict({"matches": "no"}),
        verdict("{not json"),
        verdict({"matches": True}, name="something_else"),
        answer("Looks fine to me."),
    ],
)
def test_a_malformed_verdict_is_a_failure_not_a_finding(response):
    with pytest.raises(ConsultFailed):
        observe(response)
