"""The Jev classifier through OpenRouter System One, and how the provider is picked.

Everything runs on the real openai SDK over a mock transport: no network.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re

import httpx2
import pytest
from openai import AsyncOpenAI
from voice_broker.config import DecisionsProvider, JevProvider, Routing
from voice_broker.routing import (
    CHOICES,
    INSTRUCTIONS,
    OPENROUTER_BASE_URL,
    DecisionsRouter,
    JevRouter,
    RouteRequest,
    RoutingFailed,
    router,
)

KEY = "sk-or-v1-0123456789abcdef"
REQUEST = RouteRequest(
    "Kitchen.", (("user", "Turn on the light."), ("assistant", "Which light?")), "Kitchen", "Which light?"
)


def answer(choice="ha", confidence=0.9, kind="choice") -> dict:
    # The System One shape the frozen benchmarks parsed: answers keyed by question name.
    return {
        "id": "gen-1",
        "model": "typesafe/jev-1.13-20260917",
        "provider": "TypeSafe",
        "answers": {
            "route": {
                "type": kind,
                "choice": choice,
                "probabilities": [{"value": choice, "probability": 0.9}],
                "confidence": confidence,
            }
        },
        "usage": {"input_tokens": 520, "output_tokens": 40, "cost": 0.0000218},
    }


class Wire:
    """A mock transport that records every request and answers with `respond`."""

    def __init__(self, respond, delay: float = 0.0) -> None:
        self.respond, self.delay = respond, delay
        self.requests: list[httpx2.Request] = []
        self.http = httpx2.AsyncClient(transport=httpx2.MockTransport(self._handle))

    async def _handle(self, request: httpx2.Request) -> httpx2.Response:
        self.requests.append(request)
        await asyncio.sleep(self.delay)
        return self.respond(request)

    def jev(self, timeout_s: float = 30.0) -> JevRouter:
        client = AsyncOpenAI(api_key=KEY, base_url=OPENROUTER_BASE_URL, http_client=self.http)
        return JevRouter(client, "typesafe/jev-1.13", timeout_s)


def route(wire: Wire, timeout_s: float = 30.0, request: RouteRequest = REQUEST):
    async def go():
        jev = wire.jev(timeout_s)
        try:
            return await jev.route(request)
        finally:
            await jev.aclose()

    return asyncio.run(go())


def test_one_system_one_post_with_the_policy_and_the_evidence():
    wire = Wire(lambda _: httpx2.Response(200, json=answer("ha", 0.84)))

    decision = route(wire)

    assert (decision.route, decision.confidence) == ("ha", 0.84)
    (request,) = wire.requests
    assert request.method == "POST"
    # System One, not chat completions.
    assert str(request.url) == "https://openrouter.ai/api/v1/systemone"
    assert request.headers["authorization"] == f"Bearer {KEY}"
    body = json.loads(request.content)
    assert body == {
        "model": "typesafe/jev-1.13",
        "state": {
            "text": "Kitchen.",
            "context": [{"role": "user", "text": "Turn on the light."}, {"role": "assistant", "text": "Which light?"}],
            "area": "Kitchen",
            "pending_question": "Which light?",
        },
        "questions": {"route": {"type": "choice", "instructions": INSTRUCTIONS, "criteria": CHOICES}},
    }


def test_the_limit_replaces_every_phase_of_the_request():
    wire = Wire(lambda _: httpx2.Response(200, json=answer("openclaw")))

    assert route(wire, timeout_s=30.0).route == "openclaw"

    assert wire.requests[0].extensions["timeout"] == dict.fromkeys(["connect", "read", "write", "pool"], 30.0)


@pytest.mark.parametrize("route_", ["ha", "openclaw", "clarify"])
def test_each_route_comes_through(route_):
    assert route(Wire(lambda _: httpx2.Response(200, json=answer(route_)))).route == route_


def test_the_undated_model_is_accepted_too():
    # answer() names the dated endpoint, as every benchmark and probe answer did.
    result = answer("openclaw")
    result["model"] = "typesafe/jev-1.13"
    assert route(Wire(lambda _: httpx2.Response(200, json=result))).route == "openclaw"


def test_a_missing_confidence_is_allowed():
    result = answer("clarify")
    del result["answers"]["route"]["confidence"]

    assert route(Wire(lambda _: httpx2.Response(200, json=result))).confidence is None


@pytest.mark.parametrize("status", [401, 402, 403, 429, 500, 503])
def test_a_refusal_is_one_request_never_retried_and_names_only_its_status(status, caplog):
    secret_text = f"key {KEY} has no credits for: Kitchen."
    wire = Wire(lambda _: httpx2.Response(status, json={"error": {"code": status, "message": secret_text}}))

    with caplog.at_level(logging.DEBUG), pytest.raises(RoutingFailed) as caught:
        route(wire)

    assert len(wire.requests) == 1
    assert re.fullmatch(rf"\w+Error {status} after \d+ ms", str(caught.value))
    for leak in (KEY, "credits", "Kitchen"):
        assert leak not in str(caught.value) and leak not in caplog.text


def test_a_slow_answer_times_out_and_says_after_how_long():
    wire = Wire(lambda _: httpx2.Response(200, json=answer()), delay=1.0)

    with pytest.raises(RoutingFailed) as caught:
        route(wire, timeout_s=0.05)

    assert re.fullmatch(r"(TimeoutError|APITimeoutError) after \d+ ms", str(caught.value))
    assert len(wire.requests) == 1


def test_an_unreachable_provider_fails_once():
    def refuse(request: httpx2.Request) -> httpx2.Response:
        raise httpx2.ConnectError("no route to host", request=request)

    wire = Wire(refuse)
    with pytest.raises(RoutingFailed, match=r"^APIConnectionError after \d+ ms$"):
        route(wire)
    assert len(wire.requests) == 1


def test_a_body_that_is_not_json_fails():
    wire = Wire(lambda _: httpx2.Response(200, content=b'{"answers": {', headers={"content-type": "application/json"}))

    with pytest.raises(RoutingFailed, match=r"^\w+ after \d+ ms$"):
        route(wire)


def from_another(model: str | None) -> dict:
    result = answer()
    result["model"] = model
    return result


@pytest.mark.parametrize(
    "result",
    [
        # OpenRouter substituted the model, or named none.
        from_another("typesafe/jev-1.12-20260801"),
        from_another("openai/gpt-6-luna"),
        from_another(None),
        {k: v for k, v in answer().items() if k != "model"},
        answer(kind="refusal"),
        answer(choice="home"),
        answer(choice=None),
        answer(choice=["ha"]),
        answer(confidence=1.5),
        answer(confidence=-0.1),
        answer(confidence=float("nan")),
        answer(confidence=True),
        answer(confidence="0.9"),
        {"answers": {}},
        {"answers": {"other": answer()["answers"]["route"]}},
        # Decisions' list shape is not System One's.
        {"answers": [{"name": "route", **answer()["answers"]["route"]}]},
        {"answers": {"route": None}},
        {"answers": None},
        {},
        [],
        "ha",
        None,
    ],
)
def test_any_unexpected_answer_fails(result):
    with pytest.raises(RoutingFailed):
        route(
            Wire(
                lambda _: httpx2.Response(
                    200, content=json.dumps(result).encode(), headers={"content-type": "application/json"}
                )
            )
        )


@pytest.mark.parametrize(("code", "shown"), [(502, "502"), (f"bad {KEY}", "unknown"), (None, "unknown")])
def test_an_error_object_in_a_200_answer_fails_with_its_code_only(code, shown, caplog):
    error = {"code": code, "message": f"upstream said Kitchen {KEY}"}
    wire = Wire(lambda _: httpx2.Response(200, json={"error": error}))

    with caplog.at_level(logging.DEBUG), pytest.raises(RoutingFailed) as caught:
        route(wire)

    assert str(caught.value) == f"error answer, code {shown}"
    assert KEY not in caplog.text and "Kitchen" not in caplog.text


def test_the_refusal_text_is_not_quoted():
    result = answer(kind=f"refusal: Kitchen {KEY}")

    with pytest.raises(RoutingFailed) as caught:
        route(Wire(lambda _: httpx2.Response(200, json=result)))

    assert "Kitchen" not in str(caught.value) and KEY not in str(caught.value)


def test_a_cancelled_classification_sends_nothing_more_and_still_closes():
    wire = Wire(lambda _: httpx2.Response(200, json=answer()), delay=10.0)

    async def go():
        jev = wire.jev()
        task = asyncio.create_task(jev.route(REQUEST))
        while not wire.requests:
            await asyncio.sleep(0)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        await jev.aclose()

    asyncio.run(go())
    assert len(wire.requests) == 1
    assert wire.http.is_closed


def test_closing_the_router_closes_its_own_client():
    wire = Wire(lambda _: httpx2.Response(200, json=answer()))
    route(wire)
    assert wire.http.is_closed


@pytest.mark.parametrize("timeout_s", [0, -1, float("inf"), float("nan")])
def test_the_timeout_must_be_positive(timeout_s):
    with pytest.raises(ValueError):
        JevRouter(AsyncOpenAI(api_key=KEY, base_url=OPENROUTER_BASE_URL), "typesafe/jev-1.13", timeout_s)


# -- picking the provider ------------------------------------------------------


def routing(provider) -> Routing:
    return Routing(provider, 30.0, "pipeline", 60.0, 0.35)


def test_jev_gets_a_client_of_openrouter_with_its_own_key_and_no_retries():
    openai = AsyncOpenAI(api_key="sk-openai")

    async def go():
        picked = router(routing(JevProvider("typesafe/jev-1.13", KEY)), openai)
        try:
            return picked, picked._client  # type: ignore[attr-defined]
        finally:
            await picked.aclose()

    picked, client = asyncio.run(go())
    assert isinstance(picked, JevRouter) and picked.label == "jev typesafe/jev-1.13"
    assert str(client.base_url) == "https://openrouter.ai/api/v1/"
    assert client.api_key == KEY and client.max_retries == 0 and client.timeout == 30.0
    assert KEY not in picked.label


def test_decisions_shares_the_brokers_openai_client_and_leaves_it_open():
    openai = AsyncOpenAI(api_key="sk-openai")

    async def go():
        picked = router(routing(DecisionsProvider("gpt-6-luna")), openai)
        await picked.aclose()
        return picked

    picked = asyncio.run(go())
    assert isinstance(picked, DecisionsRouter) and picked.label == "decisions gpt-6-luna"
    assert picked._client.api_key == "sk-openai" and str(picked._client.base_url) == "https://api.openai.com/v1/"
    assert not openai.is_closed()
