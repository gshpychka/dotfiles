import asyncio

import httpx2
import pytest

from voice_broker.config import Classifier, Routing
from voice_broker.dispatch import Dispatcher
from voice_broker.router_factory import make_router
from voice_broker.routing import RouteRequest


def request():
    return RouteRequest("Turn on the lights.", (), "Room", "synthetic", "v")


def test_factory_reuses_existing_openai_key_and_pool():
    calls = []

    def handler(req):
        calls.append(req)
        assert req.headers["Authorization"] == "Bearer existing-key"
        return httpx2.Response(
            200, json={"choices": [{"finish_reason": "stop", "message": {"content": '{"route":"ha"}'}}]}
        )

    async def run():
        async with httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http:
            config = Routing(
                "classifier",
                "remote",
                {},
                classifier=Classifier("compatible", "https://api.openai.com/v1", "gpt-4.1-mini"),
            )
            result = await make_router(config, "existing-key", http).route(request())
            assert result.route == "ha"

    asyncio.run(run())
    assert len(calls) == 1


def test_shadow_candidate_never_invokes_ha():
    actions = []

    def handler(req):
        return httpx2.Response(
            200, json={"choices": [{"finish_reason": "stop", "message": {"content": '{"route":"ha"}'}}]}
        )

    async def home(req):
        raise AssertionError("shadow must never execute HA")

    async def agent(req):
        actions.append("openclaw")
        return "Done."

    async def run():
        async with httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http:
            config = Routing(
                "shadow", "remote", {}, classifier=Classifier("compatible", "https://api.openai.com/v1", "gpt-4.1-mini")
            )
            await Dispatcher(make_router(config, "key", http), home, agent).consult(request())

    asyncio.run(run())
    assert actions == ["openclaw"]


def test_no_jev_credential_or_unknown_strategy_fails_before_network():
    with pytest.raises(ValueError, match="credential"):
        make_router(
            Routing(
                "classifier", "remote", {}, classifier=Classifier("jev", "https://api.typesafe.ai/v1", "jev-latest")
            ),
            "openai-key",
            None,
        )
    with pytest.raises(ValueError):
        make_router(Routing("invented", "remote", {}), "key", None)
