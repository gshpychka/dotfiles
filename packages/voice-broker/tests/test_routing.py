"""The Decisions classifier: its request, and every answer it refuses to route on."""

from __future__ import annotations

import asyncio
import json

import httpx2
import pytest
from openai import APIConnectionError, AsyncOpenAI, PermissionDeniedError
from voice_broker.routing import CHOICES, DecisionsRouter, RouteRequest, RoutingFailed


class Client:
    """Stands in for AsyncOpenAI: records with_options and the posts made through it."""

    def __init__(self, result=None, error: Exception | None = None, delay: float = 0.0) -> None:
        self.result, self.error, self.delay = result, error, delay
        self.options: dict = {}
        self.posts: list[tuple[str, dict]] = []

    def with_options(self, **options) -> Client:
        self.options = options
        return self

    async def post(self, path: str, *, cast_to, body: dict):
        assert cast_to is object
        self.posts.append((path, body))
        await asyncio.sleep(self.delay)
        if self.error is not None:
            raise self.error
        return self.result


def answer(choice="ha", confidence=0.8, kind="choice") -> dict:
    return {
        "answers": [
            {
                "type": kind,
                "name": "route",
                "choice": choice,
                "probabilities": [{"value": choice, "probability": 0.8}],
                "confidence": confidence,
            }
        ],
        "model": "gpt-6-luna",
        "usage": {"input_tokens": 300, "output_tokens": 0},
    }


REQUEST = RouteRequest(
    "Kitchen.", (("user", "Turn on the light."), ("assistant", "Which light?")), "Kitchen", "Which light?"
)


def route(client: Client, request: RouteRequest = REQUEST, timeout_s: float = 1.5):
    return asyncio.run(DecisionsRouter(client, "gpt-6-luna", timeout_s).route(request))  # type: ignore[arg-type]


def test_the_request_is_one_choice_question_over_the_conversation():
    client = Client(answer("ha", 0.72))

    decision = route(client)

    assert (decision.route, decision.confidence) == ("ha", 0.72)
    assert client.options == {"timeout": 1.5, "max_retries": 0}
    ((path, body),) = client.posts
    assert path == "/decisions" and body["model"] == "gpt-6-luna"
    (question,) = body["questions"]
    assert question["type"] == "choice" and question["name"] == "route"
    assert [c["value"] for c in question["choices"]] == ["ha", "openclaw", "clarify"]
    assert json.loads(body["input"]) == {
        "text": "Kitchen.",
        "context": [{"role": "user", "text": "Turn on the light."}, {"role": "assistant", "text": "Which light?"}],
        "area": "Kitchen",
        "pending_question": "Which light?",
    }


def test_no_pending_question_is_left_out_and_context_is_bounded():
    client = Client(answer("openclaw"))
    context = tuple(("user", f"turn {i}") for i in range(30))

    route(client, RouteRequest("What's new?", context, "Room"))

    evidence = json.loads(client.posts[0][1]["input"])
    assert "pending_question" not in evidence
    assert [t["text"] for t in evidence["context"]] == [f"turn {i}" for i in range(18, 30)]


def test_the_policy_sends_mixed_and_ambiguous_home_requests_where_they_belong():
    assert "mixes home control with any non-home work" in CHOICES["openclaw"]
    assert "ambiguous home command" in CHOICES["ha"]


@pytest.mark.parametrize(
    "result",
    [
        answer(kind="refusal"),
        answer(choice="home"),
        answer(confidence=1.5),
        answer(confidence=float("nan")),
        answer(confidence=True),
        {"answers": []},
        {"answers": [answer()["answers"][0], answer()["answers"][0]]},
        {"error": "nope"},
        None,
        [],
    ],
)
def test_any_unexpected_answer_fails(result):
    with pytest.raises(RoutingFailed):
        route(Client(result))


def test_a_missing_confidence_is_allowed():
    result = answer("clarify")
    del result["answers"][0]["confidence"]

    assert route(Client(result)).confidence is None


REQ = httpx2.Request("POST", "https://api.openai.com/v1/decisions")


@pytest.mark.parametrize(
    "error",
    [
        # The intermittent scope refusal seen on 2026-10-16.
        PermissionDeniedError(
            "The API key requires the api.decisions.write permission.",
            response=httpx2.Response(403, request=REQ),
            body=None,
        ),
        APIConnectionError(request=REQ),
    ],
)
def test_api_errors_fail_without_their_message(error):
    with pytest.raises(RoutingFailed) as caught:
        route(Client(error=error))

    assert "permission" not in str(caught.value) and "decisions" not in str(caught.value)


def test_a_slow_answer_times_out():
    with pytest.raises(RoutingFailed):
        route(Client(answer(), delay=1.0), timeout_s=0.05)


def test_the_real_client_is_configured_without_retries():
    router = DecisionsRouter(AsyncOpenAI(api_key="sk-test"), "gpt-6-luna", 1.5)

    assert router._client.max_retries == 0 and router._client.timeout == 1.5


@pytest.mark.parametrize("timeout_s", [0, -1, float("inf"), float("nan")])
def test_the_timeout_must_be_positive(timeout_s):
    with pytest.raises(ValueError):
        DecisionsRouter(Client(), "gpt-6-luna", timeout_s)  # type: ignore[arg-type]
