"""Explicit provider selection, pooled HTTP, no model/provider fallback."""

from __future__ import annotations

import logging

from .classifier import JevRouter, OpenAICompatibleRouter, OpenAIDecisionsRouter, httpx_transport
from .config import Routing
from .routing import NaiveRouter, RouteDecision, Router, RouteRequest

log = logging.getLogger(__name__)


class ShadowRouter:
    """Measure a candidate while only the existing OpenClaw backend executes."""

    def __init__(self, candidate: Router) -> None:
        self._candidate = candidate

    async def route(self, request: RouteRequest) -> RouteDecision:
        decision = await self._candidate.route(request)
        log.info("shadow candidate_route=%s route_ms=%.1f executed_route=openclaw", decision.route, decision.elapsed_ms)
        return RouteDecision("openclaw", decision.elapsed_ms)


def make_router(config: Routing, openai_key: str, http_client) -> Router:
    if config.strategy == "naive":
        return NaiveRouter()
    if config.strategy not in {"classifier", "shadow"} or config.classifier is None:
        raise ValueError("select naive, classifier or shadow with explicit classifier configuration")
    provider = config.classifier
    token = provider.token
    if token is None and provider.base_url.rstrip("/") == "https://api.openai.com/v1":
        token = openai_key
    if provider.provider == "jev" and not token:
        raise ValueError("Jev requires an explicitly configured credential file")
    transport = httpx_transport(http_client, provider.base_url, token)
    common = {"timeout_s": provider.timeout_s}
    if provider.provider == "decisions":
        router = OpenAIDecisionsRouter(transport, model=provider.model, **common)
    elif provider.provider == "jev":
        router = JevRouter(transport, model=provider.model, **common)
    elif provider.provider == "compatible":
        router = OpenAICompatibleRouter(transport, model=provider.model, api=provider.api, **common)
    else:
        raise ValueError("unknown classifier provider; no fallback is configured")
    return ShadowRouter(router) if config.strategy == "shadow" else router
