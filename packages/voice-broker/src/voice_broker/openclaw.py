"""The OpenClaw agent, which carries out the work GPT-Live delegates.

Each consult is one agent turn on the gateway's OpenResponses endpoint
(https://docs.openclaw.ai/gateway/openresponses-http-api), in the session the
config names. The gateway takes the agent, and with it the agent's tools, from
that session key's `agent:<id>:` prefix alone: `model` and the request's own
tools don't narrow the agent's native or MCP tools. So the voice agent's lack of
home-action tools is the gateway's tool policy for that agent (my.voice-broker in
the Nix config), not this client's doing. The voice starts with the newest turns
of the history session.
"""

from __future__ import annotations

import json
import logging
import time
from typing import Any, Literal
from urllib.parse import quote

import httpx2
from openai import AsyncOpenAI, OpenAIError

from .config import OpenClaw as OpenClawConfig

log = logging.getLogger(__name__)

# The gateway's default agent.
_AGENT = "openclaw"
# One agent turn, which may run several tools.
_TIMEOUT_S = 90.0
# One read of the session's transcript.
_HISTORY_TIMEOUT_S = 10.0
# One observation: a few reads of the home's state.
_OBSERVE_TIMEOUT_S = 45.0

# The observer's answer, as the one client tool it must call.
_VERDICT_TOOL: dict[str, Any] = {
    "type": "function",
    "name": "home_verdict",
    "description": "Report whether the home's current state matches what the user asked for.",
    "parameters": {
        "type": "object",
        "properties": {
            "matches": {"type": "boolean", "description": "True when the state matches, or when it can't be told."},
            "discrepancy": {
                "type": "string",
                "description": "When it does not match: one short spoken sentence for the user saying what differs.",
            },
        },
        "required": ["matches"],
        "additionalProperties": False,
    },
}
_OBSERVER_INSTRUCTIONS = (
    "You check, read-only, what Home Assistant just did after a spoken request. Home Assistant alone acts on the "
    "home; you never change anything and never ask it to. Read the current state of the devices involved, then "
    "call home_verdict once. Report matches=false only for a clear, concrete difference between what the user "
    "asked and the state now, such as the wrong room's light or a device left off. Speech recognition can "
    "mishear, so when the request is unclear, or the state can't be read, report matches=true."
)

Role = Literal["user", "assistant"]
# One message of a conversation: who said it and what.
Turn = tuple[Role, str]
# Transcript roles whose text is conversation; tool results have a role of their own.
_ROLES: dict[str, Role] = {"user": "user", "assistant": "assistant"}


class ConsultFailed(Exception):
    """The agent gave no answer."""


class HistoryUnavailable(Exception):
    """The agent's conversation could not be read."""


class OpenClaw:
    def __init__(self, config: OpenClawConfig, http_client: httpx2.AsyncClient | None = None) -> None:
        self._config = config
        self._http = http_client or httpx2.AsyncClient()
        self._client = AsyncOpenAI(
            base_url=f"{config.url}/v1",
            api_key=config.token,
            default_headers={
                "x-openclaw-session-key": config.session_key,
                **({} if config.agent is None else {"x-openclaw-agent-id": config.agent}),
                **({} if config.model is None else {"x-openclaw-model": config.model}),
            },
            timeout=_TIMEOUT_S,
            # An agent turn can act on the home, so a retried one could act twice.
            max_retries=0,
            http_client=self._http,
        )

    async def consult(self, task: str) -> str:
        """The agent's answer to `task`, to be spoken."""
        try:
            response = await self._client.responses.create(
                model=_AGENT, input=task, instructions=self._config.instructions
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

    async def observe(self, evidence: str) -> str | None:
        """Whether the home now matches what the user asked: None, or the discrepancy to tell them.

        A turn of the observer session. The agent reads the home with its own
        read-only tools, and answers through one client function call that
        tool_choice requires (openresponses-http-api.md), so its verdict is
        structured rather than parsed from prose. Raises ConsultFailed.
        """
        assert self._config.observer_session_key is not None
        try:
            response = await self._client.responses.create(
                model=_AGENT,
                input=evidence,
                instructions=_OBSERVER_INSTRUCTIONS,
                tools=[_VERDICT_TOOL],
                tool_choice={"type": "function", "name": _VERDICT_TOOL["name"]},
                extra_headers={"x-openclaw-session-key": self._config.observer_session_key},
                timeout=_OBSERVE_TIMEOUT_S,
            )
        except OpenAIError as e:
            raise ConsultFailed(repr(e)) from e
        calls = [item for item in response.output if getattr(item, "type", None) == "function_call"]
        if len(calls) != 1 or calls[0].name != _VERDICT_TOOL["name"]:
            raise ConsultFailed(f"the observer gave {len(calls)} verdicts")
        try:
            verdict = json.loads(calls[0].arguments)
            matches = verdict["matches"]
            discrepancy = str(verdict.get("discrepancy") or "").strip()
        except (ValueError, LookupError, TypeError) as e:
            raise ConsultFailed(f"malformed verdict: {type(e).__name__}") from e
        if matches is True:
            return None
        if matches is not False or not discrepancy:
            raise ConsultFailed("verdict without a discrepancy")
        log.info("observer -> %s", discrepancy)
        return discrepancy

    async def recent(self) -> list[Turn]:
        """The newest turns of the agent's conversation, within the configured history bounds."""
        history = self._config.history
        session = quote(self._config.history_session_key or self._config.session_key, safe="")
        try:
            response = await self._http.get(
                f"{self._config.url}/sessions/{session}/history",
                params={"limit": history.max_messages},
                headers={"Authorization": f"Bearer {self._config.token}"},
                timeout=_HISTORY_TIMEOUT_S,
            )
            response.raise_for_status()
            messages = response.json()["messages"]
        except (httpx2.HTTPError, LookupError, TypeError, ValueError) as e:
            raise HistoryUnavailable(repr(e)) from e
        if not isinstance(messages, list):
            raise HistoryUnavailable(f"history messages are {type(messages).__name__}")
        turns = _turns(messages, since=time.time() - history.max_age_s)
        return _newest(turns, history.max_chars)

    async def aclose(self) -> None:
        # closes the HTTP client with it
        await self._client.close()


def _turns(messages: list[Any], since: float) -> list[Turn]:
    """The conversation in `messages`, in order: each user or assistant message's text, from `since` on."""
    turns: list[Turn] = []
    for message in messages:
        if not isinstance(message, dict):
            continue
        role = _ROLES.get(message.get("role"))
        timestamp = message.get("timestamp")
        if role is None or (isinstance(timestamp, int | float) and timestamp / 1000 < since):
            continue
        text = "\n".join(_texts(message.get("content")))
        if text:
            turns.append((role, text))
    return turns


def _texts(content: Any) -> list[str]:
    """The text parts of a message's content, blank ones left out."""
    parts = content if isinstance(content, list) else [{"type": "text", "text": content}]
    texts = [
        part["text"].strip()
        for part in parts
        if isinstance(part, dict) and part.get("type") == "text" and isinstance(part.get("text"), str)
    ]
    return [text for text in texts if text]


def _newest(turns: list[Turn], max_chars: int) -> list[Turn]:
    """The longest tail of `turns` whose text fits in `max_chars`."""
    kept = 0
    chars = 0
    for _, text in reversed(turns):
        chars += len(text)
        if chars > max_chars:
            break
        kept += 1
    return turns[len(turns) - kept :]
