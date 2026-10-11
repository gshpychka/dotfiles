"""The OpenClaw agent, which carries out the work GPT-Live delegates.

Each consult is one agent turn on the gateway's OpenResponses endpoint
(https://docs.openclaw.ai/gateway/openresponses-http-api).
"""

from __future__ import annotations

import logging

import httpx2
from openai import AsyncOpenAI, OpenAIError

from .config import OpenClaw as OpenClawConfig

log = logging.getLogger(__name__)

# The gateway's default agent.
_AGENT = "openclaw"
# The OpenResponses `user`, which keys the agent session; every Voice PE shares it.
_SESSION = "voice"
# One agent turn, which may run several tools.
_TIMEOUT_S = 90.0


class ConsultFailed(Exception):
    """The agent gave no answer."""


class OpenClaw:
    def __init__(self, config: OpenClawConfig, http_client: httpx2.AsyncClient | None = None) -> None:
        self._client = AsyncOpenAI(
            base_url=f"{config.url}/v1",
            api_key=config.token,
            default_headers={} if config.model is None else {"x-openclaw-model": config.model},
            timeout=_TIMEOUT_S,
            # An agent turn can act on the home, so a retried one could act twice.
            max_retries=0,
            http_client=http_client,
        )
        self._instructions = config.instructions

    async def consult(self, task: str) -> str:
        """The agent's answer to `task`, to be spoken."""
        try:
            response = await self._client.responses.create(
                model=_AGENT, input=task, instructions=self._instructions, user=_SESSION
            )
        except OpenAIError as e:
            raise ConsultFailed(repr(e)) from e
        if response.status != "completed":
            log.warning("consult ended %s: %s", response.status, response.error)
        answer = response.output_text.strip()
        if not answer:
            raise ConsultFailed(f"the agent's turn ended {response.status} with no text")
        log.info("consult -> %s", answer)
        return answer

    async def aclose(self) -> None:
        await self._client.close()
