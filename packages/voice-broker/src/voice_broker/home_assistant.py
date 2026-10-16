"""Home Assistant's conversation agent, through Assist's WebSocket API, text in and text out.

One `assist_pipeline/run` from the intent stage to the intent stage
(https://contributors.home-assistant.io/core/internals/assist-pipelines/), so Home
Assistant's own speech recognition and TTS stay out: GPT-Live hears and speaks.
The pipeline's conversation agent is an LLM that may act, answer or ask back
(`continue_conversation`, https://contributors.home-assistant.io/core/internals/conversation-api/).
A run that fails or times out may still have acted, so it is never retried.
"""

from __future__ import annotations

import asyncio
import json
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlsplit, urlunsplit

from websockets.asyncio.client import connect
from websockets.exceptions import WebSocketException

# One run, LLM tool calls included.
_TIMEOUT_S = 20.0
# Home Assistant's own run timeout, just inside ours so its error arrives first.
_RUN_TIMEOUT_S = _TIMEOUT_S - 1
_COMMAND_ID = 1


class HomeAssistantFailed(Exception):
    """No answer from Home Assistant; it may still have acted."""


@dataclass(frozen=True, slots=True)
class HomeReply:
    # What to tell the user: a result, or the question Home Assistant asks.
    speech: str
    # Continues this exchange in Home Assistant's chat session.
    conversation_id: str | None
    # Home Assistant expects the user's answer.
    continue_conversation: bool


class HomeAssistant:
    """The conversation agent as seen from one Voice PE."""

    def __init__(
        self, url: str, token: str, pipeline: str, device_id: str, connector: Callable[..., Any] = connect
    ) -> None:
        parts = urlsplit(url)
        self._url = urlunsplit(("wss" if parts.scheme == "https" else "ws", parts.netloc, "/api/websocket", "", ""))
        self._token = token
        self._pipeline = pipeline
        # The Voice PE's ESPHome device: Home Assistant resolves its area and unplaced requests by it.
        self._device_id = device_id
        self._connect = connector

    async def converse(self, text: str, conversation_id: str | None) -> HomeReply:
        """The agent's reply to `text`, continuing `conversation_id` when given."""
        command: dict[str, Any] = {
            "id": _COMMAND_ID,
            "type": "assist_pipeline/run",
            "pipeline": self._pipeline,
            "start_stage": "intent",
            "end_stage": "intent",
            "input": {"text": text},
            "device_id": self._device_id,
            "timeout": _RUN_TIMEOUT_S,
        }
        if conversation_id is not None:
            command["conversation_id"] = conversation_id
        try:
            async with asyncio.timeout(_TIMEOUT_S):
                async with self._connect(self._url, max_size=2**20, open_timeout=5) as ws:
                    await self._authenticate(ws)
                    await ws.send(json.dumps(command))
                    return await self._reply(ws)
        # AttributeError: a frame that is JSON but not an object.
        except (TimeoutError, OSError, WebSocketException, ValueError, LookupError, TypeError, AttributeError) as e:
            raise HomeAssistantFailed(type(e).__name__) from e

    async def _authenticate(self, ws: Any) -> None:
        if json.loads(await ws.recv()).get("type") != "auth_required":
            raise HomeAssistantFailed("no auth_required")
        await ws.send(json.dumps({"type": "auth", "access_token": self._token}))
        if json.loads(await ws.recv()).get("type") != "auth_ok":
            raise HomeAssistantFailed("authentication refused")

    async def _reply(self, ws: Any) -> HomeReply:
        output: dict[str, Any] | None = None
        async for raw in ws:
            message = json.loads(raw)
            if message.get("id") != _COMMAND_ID:
                continue
            if message.get("type") == "result":
                if not message.get("success"):
                    raise HomeAssistantFailed("run refused")
                continue
            event = message.get("event") or {}
            match event.get("type"):
                case "error":
                    raise HomeAssistantFailed(f"run error {(event.get('data') or {}).get('code')}")
                case "intent-end":
                    output = event["data"]["intent_output"]
                case "run-end":
                    if output is None:
                        raise HomeAssistantFailed("run ended without an intent result")
                    return _home_reply(output)
        raise HomeAssistantFailed("disconnected before the run ended")


def _home_reply(output: dict[str, Any]) -> HomeReply:
    response = output.get("response") or {}
    speech = (((response.get("speech") or {}).get("plain") or {}).get("speech") or "").strip()
    error = response.get("response_type") == "error"
    if not speech:
        speech = "Home Assistant could not do that." if error else "Home Assistant gave no answer."
    conversation_id = output.get("conversation_id")
    return HomeReply(
        speech=speech,
        conversation_id=conversation_id if isinstance(conversation_id, str) and conversation_id else None,
        # A question without an ID to answer it under cannot be continued.
        continue_conversation=output.get("continue_conversation") is True and bool(conversation_id) and not error,
    )
