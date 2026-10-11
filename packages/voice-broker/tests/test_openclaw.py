"""The consult client against a mocked OpenResponses endpoint."""

from __future__ import annotations

import asyncio
import json

import httpx2
import pytest
from voice_broker.config import OpenClaw as OpenClawConfig
from voice_broker.openclaw import ConsultFailed, OpenClaw


def config(model: str | None = None) -> OpenClawConfig:
    return OpenClawConfig(url="http://openclaw.test", token="gateway-secret", instructions="Be brief.", model=model)


def consult(handler, model: str | None = None) -> str:
    async def main() -> str:
        http_client = httpx2.AsyncClient(transport=httpx2.MockTransport(handler))
        client = OpenClaw(config(model), http_client=http_client)
        try:
            return await client.consult("Turn off the lights.")
        finally:
            await client.aclose()

    return asyncio.run(main())


def answer(text: str, status: str = "completed") -> dict:
    return {
        "id": "resp_1",
        "object": "response",
        "status": status,
        "output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": text}]}],
    }


def test_a_consult_is_one_turn_of_the_shared_voice_session():
    requests: list[httpx2.Request] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        requests.append(request)
        return httpx2.Response(200, json=answer("The lights are off."))

    assert consult(handler) == "The lights are off."
    (request,) = requests
    assert str(request.url) == "http://openclaw.test/v1/responses"
    assert request.headers["authorization"] == "Bearer gateway-secret"
    # The agent keeps its own model unless one is configured.
    assert "x-openclaw-model" not in request.headers
    assert json.loads(request.content) == {
        "model": "openclaw",
        "input": "Turn off the lights.",
        "instructions": "Be brief.",
        "user": "voice",
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
