"""The agent client against a mocked gateway."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from collections.abc import Awaitable, Callable

import httpx2
import pytest
from voice_broker.config import History
from voice_broker.config import OpenClaw as OpenClawConfig
from voice_broker.config import Overflow
from voice_broker import openclaw as openclaw_module
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


# -- a conversation's session: main's, or its own when main's is full ------------

PREFIX = "agent:main:voice-overflow:"
OVERFLOW = Overflow(session_prefix=PREFIX, handoff_max_chars=60, fits_when_unknown=True, margin_tokens=0)
# The gateway's own budget for main on hoard, 2026-10-17: 500000, compacting past 480000.
WINDOW = 500_000
THRESHOLD = 480_000
UNKNOWN_OVERFLOWS = Overflow(PREFIX, 60, fits_when_unknown=False, margin_tokens=0)


def usage(prompt_and_output: int, state: str = "available") -> dict:
    return {"input": 1, "output": 1, "contextUsage": {"state": state, "totalTokens": prompt_and_output}}


class Gateway:
    """The gateway's sessions_list, main's transcript and its turns, recording each request."""

    def __init__(
        self,
        *,
        window: int | None = WINDOW,
        row_total: int | None = None,
        messages: list[dict] | None = None,
        rows: list[dict] | None = None,
        consult: Handler | None = None,
    ) -> None:
        self.window = window
        self.row_total = row_total
        self.messages = messages if messages is not None else []
        self.rows = rows
        self.consult = consult
        self.requests: list[httpx2.Request] = []
        # What each turn was sent: (session key, input).
        self.turns: list[tuple[str, str]] = []

    def __call__(self, request: httpx2.Request) -> httpx2.Response:
        self.requests.append(request)
        match request.url.path:
            case "/tools/invoke":
                return httpx2.Response(200, json={"ok": True, "result": {"details": {"sessions": self._rows()}}})
            case "/sessions/agent:main:main/history":
                return httpx2.Response(200, json={"messages": self.messages})
            case "/v1/responses":
                self.turns.append((request.headers["x-openclaw-session-key"], json.loads(request.content)["input"]))
                if self.consult is not None:
                    return self.consult(request)
                return httpx2.Response(200, json=answer("Done."))
        return httpx2.Response(404, json={"ok": False})

    def _rows(self) -> list[dict]:
        if self.rows is not None:
            return self.rows
        row: dict = {"key": "main", "agentId": "main", "kind": "direct"}
        if self.window is not None:
            row["contextTokens"] = self.window
        if self.row_total is not None:
            row["totalTokens"] = self.row_total
        return [row]

    def paths(self) -> list[str]:
        return [r.url.path for r in self.requests]


def main_config(overflow: Overflow | None = OVERFLOW) -> OpenClawConfig:
    base = config()
    return OpenClawConfig(
        **{**{f: getattr(base, f) for f in base.__slots__}, "agent": "main", "overflow": overflow, "instructions": ""}
    )


def with_gateway[T](gateway: Gateway, use: Callable[[OpenClaw], Awaitable[T]], cfg: OpenClawConfig | None = None) -> T:
    async def main() -> T:
        client = OpenClaw(cfg or main_config(), http_client=httpx2.AsyncClient(transport=httpx2.MockTransport(gateway)))
        try:
            return await use(client)
        finally:
            await client.aclose()

    return asyncio.run(main())


def first_consult(gateway: Gateway, task: str = "Will it rain?", cfg: OpenClawConfig | None = None) -> str | None:
    """The session a conversation's first consult of `task` went to."""

    async def use(client: OpenClaw) -> str | None:
        conversation = client.conversation("room-assistant-1")
        await conversation.consult(task)
        return conversation.session_key

    return with_gateway(gateway, use, cfg)


def test_a_conversation_consults_mains_own_session_while_it_has_room():
    gateway = Gateway(
        row_total=200_000, messages=[message("assistant", text("Hi"), age_s=60) | {"usage": usage(237_000)}]
    )

    assert first_consult(gateway) == "agent:main:main"
    # The preflight reads, both before the conversation's first request.
    assert gateway.paths() == ["/tools/invoke", "/sessions/agent:main:main/history", "/v1/responses"]
    assert gateway.turns == [("agent:main:main", "Will it rain?")]
    turn = gateway.requests[-1]
    # Main, named and by the key's prefix, which is what picks the agent.
    assert turn.headers["x-openclaw-agent-id"] == "main"
    invoke = json.loads(gateway.requests[0].content)
    assert invoke == {
        "tool": "sessions_list",
        "args": {"agentId": "main", "search": "agent:main:main", "limit": 5},
        "sessionKey": "agent:main:main",
    }
    assert gateway.requests[0].headers["authorization"] == "Bearer gateway-secret"


def test_the_consults_own_size_counts_against_the_room_left():
    # 1000 tokens below the threshold: a short consult fits, one of 1000 bytes or more doesn't.
    newest = [message("assistant", text("ok"), age_s=1) | {"usage": usage(THRESHOLD - 1000)}]
    assert first_consult(Gateway(messages=newest), task="x" * 999) == "agent:main:main"
    assert first_consult(Gateway(messages=newest), task="x" * 1000) == f"{PREFIX}room-assistant-1"
    # Multi-byte speech counts by its bytes: 500 Cyrillic letters are 1000 bytes.
    assert first_consult(Gateway(messages=newest), task="ж" * 500) == f"{PREFIX}room-assistant-1"


def test_the_consult_instructions_count_too():
    newest = [message("assistant", text("ok"), age_s=1) | {"usage": usage(THRESHOLD - 1000)}]
    base = main_config()
    long = OpenClawConfig(**{**{f: getattr(base, f) for f in base.__slots__}, "instructions": "i" * 990})
    assert first_consult(Gateway(messages=newest), task="x" * 9, cfg=long) == "agent:main:main"
    assert first_consult(Gateway(messages=newest), task="x" * 10, cfg=long) == f"{PREFIX}room-assistant-1"


def test_the_larger_of_the_rows_prompt_and_the_newest_calls_counts():
    # The row's prompt (completion excluded) can lag the transcript, or lead it: the larger decides.
    lagging = Gateway(row_total=100_000, messages=[message("assistant", text("ok")) | {"usage": usage(THRESHOLD)}])
    assert first_consult(lagging) == f"{PREFIX}room-assistant-1"
    leading = Gateway(row_total=THRESHOLD, messages=[message("assistant", text("ok")) | {"usage": usage(1000)}])
    assert first_consult(leading) == f"{PREFIX}room-assistant-1"


def test_messages_after_the_newest_recorded_call_count_by_their_bytes():
    after = message("user", text("y" * 2000), age_s=0)
    gateway = Gateway(messages=[message("assistant", text("ok")) | {"usage": usage(THRESHOLD - 1500)}, after])
    assert first_consult(gateway) == f"{PREFIX}room-assistant-1"
    # Without a recorded call among those read, what precedes them isn't known: unknown, whatever the row says.
    unrecorded = Gateway(row_total=10, messages=[after])
    assert first_consult(unrecorded, cfg=main_config(UNKNOWN_OVERFLOWS)) == f"{PREFIX}room-assistant-1"
    assert first_consult(Gateway(row_total=10, messages=[after])) == "agent:main:main"


def test_an_unavailable_usage_record_is_not_a_measurement():
    stale = Gateway(row_total=None, messages=[message("assistant", text("ok")) | {"usage": usage(THRESHOLD, "stale")}])
    # No usable number at all: unknown, and here (fits_when_unknown) main.
    assert first_consult(stale) == "agent:main:main"


def test_a_small_window_reserves_a_quarter():
    # 40000 tokens: the reserve is 10000, not 20000, so the threshold is 30000.
    newest = [message("assistant", text("ok")) | {"usage": usage(25_000)}]
    assert first_consult(Gateway(window=40_000, messages=newest)) == "agent:main:main"
    assert first_consult(Gateway(window=40_000, messages=newest), task="x" * 5000) == f"{PREFIX}room-assistant-1"


def test_a_full_main_session_gets_the_conversation_its_own_with_a_bounded_handoff():
    old = [
        message("user", text("an old Telegram question that is long enough to be left out")),
        message("assistant", text("Mum lands at six.")),
        message("user", text("Remind me at five.")),
        message("assistant", text("Will do.")) | {"usage": usage(THRESHOLD + 5)},
    ]
    gateway = Gateway(messages=old)

    assert first_consult(gateway) == f"{PREFIX}room-assistant-1"
    ((session, sent),) = gateway.turns
    assert session == f"{PREFIX}room-assistant-1"
    handoff, request = sent.rsplit("\n\n", 1)
    lead, said = handoff.split("\n", 1)
    assert lead.startswith("Your main session is too full")
    assert request == "Will it rain?"
    # The newest of main's messages within the 60-character bound, oldest kept first; no more.
    assert said == "assistant: Mum lands at six.\nuser: Remind me at five.\nassistant: Will do."
    assert "old Telegram" not in sent
    # The same agent: the overflow key is main's, and main is named.
    assert gateway.requests[-1].headers["x-openclaw-agent-id"] == "main"


def test_unknown_use_follows_the_configured_policy_and_says_so(caplog):
    def broken(request: httpx2.Request) -> httpx2.Response:
        if request.url.path == "/tools/invoke":
            return httpx2.Response(500, json={"ok": False})
        return Gateway()(request)

    to_main = main_config(Overflow(PREFIX, 60, fits_when_unknown=True, margin_tokens=0))
    to_overflow = main_config(Overflow(PREFIX, 60, fits_when_unknown=False, margin_tokens=0))
    caplog.set_level(logging.INFO, logger="voice_broker.openclaw")
    for handler in (broken, Gateway(window=None), Gateway(rows=[]), Gateway(row_total=None)):
        assert first_consult(handler, cfg=to_main) == "agent:main:main"  # type: ignore[arg-type]
        assert first_consult(handler, cfg=to_overflow) == f"{PREFIX}room-assistant-1"  # type: ignore[arg-type]
    assert "context use unknown" in caplog.text
    # The log carries numbers and keys, never the conversation.
    assert "Will it rain" not in caplog.text


def test_mains_row_is_found_by_its_alias_and_only_main_s():
    other = {"key": "agent:voice:main", "agentId": "voice", "contextTokens": 1, "totalTokens": 1}
    by_key = {"key": "agent:main:main", "agentId": "main", "contextTokens": WINDOW, "totalTokens": THRESHOLD}
    measured = [message("assistant", text("ok")) | {"usage": usage(1000)}]
    # The row's prompt counts when it is the larger: this row is main's, the other agent's is ignored.
    assert first_consult(Gateway(rows=[other, by_key], messages=measured)) == f"{PREFIX}room-assistant-1"
    two = {"key": "main", "agentId": "main", "contextTokens": WINDOW, "totalTokens": 1}
    # Two rows for the session can't be told apart: unknown, not a guess.
    unknown = main_config(Overflow(PREFIX, 60, fits_when_unknown=False, margin_tokens=0))
    assert first_consult(Gateway(rows=[by_key, two]), cfg=unknown) == f"{PREFIX}room-assistant-1"


def times_out(request: httpx2.Request) -> httpx2.Response:
    raise httpx2.ReadTimeout("timed out", request=request)


def overflowed(request: httpx2.Request) -> httpx2.Response:
    return httpx2.Response(500, json={"error": {"message": "context overflow"}})


@pytest.mark.parametrize("failure", [times_out, overflowed])
def test_a_failed_or_timed_out_consult_is_never_resent_to_the_overflow_session(failure: Handler):
    gateway = Gateway(messages=[message("assistant", text("ok")) | {"usage": usage(1000)}], consult=failure)

    async def use(client: OpenClaw) -> tuple[str | None, str | None]:
        conversation = client.conversation("room-assistant-1")
        with pytest.raises(ConsultFailed):
            await conversation.consult("Turn the heating up.")
        placed = conversation.session_key
        # The next request of the conversation stays where it was placed, and nothing is replayed.
        gateway.consult = None
        await conversation.consult("And the hallway?")
        return placed, conversation.session_key

    assert with_gateway(gateway, use) == ("agent:main:main", "agent:main:main")
    assert gateway.turns == [("agent:main:main", "Turn the heating up."), ("agent:main:main", "And the hallway?")]
    # One preflight, before the first request only.
    assert gateway.paths().count("/tools/invoke") == 1


def test_follow_ups_stay_in_the_overflow_session_without_a_second_handoff():
    gateway = Gateway(messages=[message("assistant", text("Will do.")) | {"usage": usage(THRESHOLD)}])

    async def use(client: OpenClaw) -> None:
        conversation = client.conversation("kitchen-assistant-7")
        await conversation.consult("What's on tonight?")
        # Main got room meanwhile: the conversation stays put, its earlier turns are in its session.
        gateway.messages = [message("assistant", text("ok")) | {"usage": usage(1000)}]
        await conversation.consult("And tomorrow?")

    with_gateway(gateway, use)
    (first, second) = gateway.turns
    assert first[0] == second[0] == f"{PREFIX}kitchen-assistant-7"
    assert first[1].startswith("Your main session is too full")
    assert second[1] == "And tomorrow?"
    assert gateway.paths().count("/tools/invoke") == 1


def test_the_next_conversation_is_placed_afresh_back_in_main_once_it_has_room():
    gateway = Gateway(messages=[message("assistant", text("ok")) | {"usage": usage(THRESHOLD)}])

    async def use(client: OpenClaw) -> list[str | None]:
        full = client.conversation("room-assistant-1")
        await full.consult("one")
        # Main compacted since.
        gateway.messages = [message("assistant", text("ok")) | {"usage": usage(40_000)}]
        later = client.conversation("room-assistant-2")
        await later.consult("two")
        return [full.session_key, later.session_key]

    assert with_gateway(gateway, use) == [f"{PREFIX}room-assistant-1", "agent:main:main"]
    assert gateway.turns[1] == ("agent:main:main", "two")


def test_two_speakers_overflow_sessions_are_their_own():
    gateway = Gateway(messages=[message("assistant", text("Will do.")) | {"usage": usage(THRESHOLD)}])

    async def use(client: OpenClaw) -> None:
        room, kitchen = client.conversation("room-assistant-1"), client.conversation("kitchen-assistant-1")
        await room.consult("Room's secret plan.")
        await kitchen.consult("What time is it?")

    with_gateway(gateway, use)
    (room, kitchen) = gateway.turns
    assert room[0] != kitchen[0]
    # A handoff is main's messages only: nothing said at the other speaker.
    assert "Room's secret plan" not in kitchen[1]


def test_two_first_consults_together_are_placed_once():
    gateway = Gateway(messages=[message("assistant", text("ok")) | {"usage": usage(THRESHOLD)}])

    async def use(client: OpenClaw) -> None:
        conversation = client.conversation("room-assistant-1")
        await asyncio.gather(conversation.consult("a"), conversation.consult("b"))

    with_gateway(gateway, use)
    assert gateway.paths().count("/tools/invoke") == 1
    assert {session for session, _ in gateway.turns} == {f"{PREFIX}room-assistant-1"}
    # One handoff, on the request sent first: the second waits until it is built.
    assert sum(sent.startswith("Your main session") for _, sent in gateway.turns) == 1
    assert gateway.turns[0][1].startswith("Your main session")


def test_the_voice_still_starts_with_mains_history_in_an_overflow_conversation():
    history = [message("user", text("Telegram hello")), message("assistant", text("ok")) | {"usage": usage(THRESHOLD)}]
    gateway = Gateway(messages=history)

    async def use(client: OpenClaw) -> list[Turn]:
        conversation = client.conversation("room-assistant-1")
        await conversation.consult("hi")
        return await conversation.recent()

    assert with_gateway(gateway, use) == [("user", "Telegram hello"), ("assistant", "ok")]
    assert gateway.paths()[-1] == "/sessions/agent:main:main/history"


def test_without_overflow_every_consult_is_mains_and_nothing_is_read_first():
    gateway = Gateway(messages=[message("assistant", text("ok")) | {"usage": usage(THRESHOLD * 2)}])
    assert first_consult(gateway, cfg=main_config(overflow=None)) == "agent:main:main"
    assert gateway.paths() == ["/v1/responses"]


class HistoryOnce(Gateway):
    """Main's transcript reads once, for the preflight, and then fails."""

    def __call__(self, request: httpx2.Request) -> httpx2.Response:
        if request.url.path.endswith("/history") and "/sessions/agent:main:main/history" in self.paths():
            self.requests.append(request)
            return httpx2.Response(503)
        return super().__call__(request)


def test_a_handoff_that_cant_be_read_doesnt_stop_the_request():
    gateway = HistoryOnce(messages=[message("assistant", text("ok")) | {"usage": usage(THRESHOLD)}])

    assert first_consult(gateway) == f"{PREFIX}room-assistant-1"
    # The overflow session starts without main's messages, and the request still goes, once.
    assert gateway.turns == [(f"{PREFIX}room-assistant-1", "Will it rain?")]


def measured_at(tokens: int) -> list[dict]:
    return [message("assistant", text("ok")) | {"usage": usage(tokens)}]


def test_the_margin_counts_what_the_gateway_adds_again():
    margin = main_config(Overflow(PREFIX, 60, fits_when_unknown=True, margin_tokens=12_000))
    assert first_consult(Gateway(messages=measured_at(THRESHOLD - 12_100)), cfg=margin) == "agent:main:main"
    assert first_consult(Gateway(messages=measured_at(THRESHOLD - 12_000)), cfg=margin) == f"{PREFIX}room-assistant-1"


@pytest.mark.parametrize(
    "newer",
    [
        # an unmeasured call after a measured one: the gateway then estimates all of it, and so can't the broker
        message("assistant", text("ok")) | {"usage": usage(0, "unavailable")},
        message("assistant", text("ok")) | {"usage": {"input": 5, "output": 1}},
        # shown cut, or with blocks the endpoint may show less of
        message("user", text("p" * 8000)),
        message("user", {"type": "image", "data": "..."}),
    ],
)
def test_use_that_cant_be_bounded_is_unknown(newer: dict):
    gateway = Gateway(messages=[*measured_at(1000), newer])
    assert first_consult(gateway, cfg=main_config(UNKNOWN_OVERFLOWS)) == f"{PREFIX}room-assistant-1"
    assert first_consult(Gateway(messages=[*measured_at(1000), newer])) == "agent:main:main"


@pytest.mark.parametrize(
    "body",
    [
        {"ok": True, "result": {"details": {"sessions": None}}},
        {"ok": True, "result": {"details": {"sessions": [{"key": ["main"], "agentId": "main"}]}}},
        {"ok": True, "result": {"details": {"sessions": [{"key": "main", "agentId": "main", "contextTokens": 1e400}]}}},
        {"ok": True, "result": {"details": {"sessions": [{"key": "main", "agentId": "main", "contextTokens": "big"}]}}},
        {"ok": True, "result": None},
        {"ok": False, "error": {"type": "tool_call_blocked"}},
        ["not", "an", "object"],
    ],
)
def test_a_malformed_or_refused_sessions_list_is_unknown_not_a_crash(body: object):
    class Odd(Gateway):
        def __call__(self, request: httpx2.Request) -> httpx2.Response:
            if request.url.path == "/tools/invoke":
                self.requests.append(request)
                return httpx2.Response(200, json=body)
            return super().__call__(request)

    assert first_consult(Odd(messages=measured_at(1000)), cfg=main_config(UNKNOWN_OVERFLOWS)) == (
        f"{PREFIX}room-assistant-1"
    )


def test_odd_numbers_are_no_numbers():
    for odd in (float("nan"), float("inf"), 1e400, -5, 2.5, True, "7"):
        assert openclaw_module._tokens(odd) is None
    assert openclaw_module._tokens(7.0) == 7


def test_an_unreachable_preflight_and_a_missing_session_are_unknown():
    class Slow(Gateway):
        def __call__(self, request: httpx2.Request) -> httpx2.Response:
            if request.url.path == "/tools/invoke":
                raise httpx2.ReadTimeout("timed out", request=request)
            return super().__call__(request)

    class Missing(Gateway):
        def __call__(self, request: httpx2.Request) -> httpx2.Response:
            if request.url.path.endswith("/history"):
                return httpx2.Response(404, json={"ok": False, "error": {"type": "not_found"}})
            return super().__call__(request)

    for gateway in (Slow(messages=measured_at(1000)), Missing()):
        assert first_consult(gateway, cfg=main_config(UNKNOWN_OVERFLOWS)) == f"{PREFIX}room-assistant-1"
        # The request still goes, exactly once.
        assert len(gateway.turns) == 1


def test_a_preflight_bug_costs_no_request(monkeypatch):
    async def broken(self, task):
        raise RuntimeError("bug")

    monkeypatch.setattr(OpenClaw, "preflight", broken)
    gateway = Gateway()
    assert first_consult(gateway) == "agent:main:main"
    assert gateway.turns == [("agent:main:main", "Will it rain?")]


def test_a_failed_first_overflow_consult_is_not_resent_and_its_follow_up_stays():
    gateway = Gateway(messages=measured_at(THRESHOLD), consult=times_out)

    async def use(client: OpenClaw) -> None:
        conversation = client.conversation("room-assistant-1")
        with pytest.raises(ConsultFailed):
            await conversation.consult("Book the table.")
        gateway.consult = None
        await conversation.consult("For two.")

    with_gateway(gateway, use)
    (first, second) = gateway.turns
    assert first[0] == second[0] == f"{PREFIX}room-assistant-1"
    assert first[1].startswith("Your main session is too full")
    # No second handoff, no replay of the failed request.
    assert second[1] == "For two."


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
