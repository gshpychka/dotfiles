"""Official Assist WebSocket API: intent to intent, no duplicate STT/TTS.

Timeout/disconnect may follow an action: NEVER retry or run another backend.
"""

from __future__ import annotations

import asyncio
import json
import re
from collections.abc import Callable
from typing import Any
from urllib.parse import urlsplit, urlunsplit

from websockets.asyncio.client import connect
from websockets.exceptions import WebSocketException

from .openclaw import ConsultFailed
from .routing import RouteRequest


class HomeAssistant:
    def __init__(
        self,
        url: str,
        token: str,
        pipeline: str,
        device_id: str,
        connector: Callable[..., Any] = connect,
        timeout_s: float = 20.0,
        is_current: Callable[[RouteRequest], bool] = lambda _: True,
    ) -> None:
        parts = urlsplit(url)
        self._url = urlunsplit(("wss" if parts.scheme == "https" else "ws", parts.netloc, "/api/websocket", "", ""))
        self._token = token
        self._pipeline = pipeline
        self._device_id = device_id
        self._connect = connector
        self._timeout_s = timeout_s
        self._conversation_id: str | None = None
        self._previous_request: str | None = None
        self._is_current = is_current

    async def consult(self, request: RouteRequest) -> str:
        if not self._pipeline or not self._device_id:
            raise ConsultFailed("Home Assistant pipeline/device not configured; no action attempted")
        # Only uninterrupted, confirmed HA turns may share HA context. When
        # another backend intervenes, discard it and require a named target.
        prior_users = [text for role, text in request.context if role == "user"]
        continuous = bool(self._conversation_id and prior_users and prior_users[-1].strip() == self._previous_request)
        conversation_id = self._conversation_id if continuous else None
        self._conversation_id = None
        self._previous_request = None
        explicit_target = re.search(
            r"\b(lights?|lamps?|fan|blinds?|curtains?|thermostat|climate|scenes?|heater|speaker|tv|sensor|temperature|humidity|weather station)\b"
            r"|світл|ламп|вентилятор|штор|термостат|клімат|сцен|опален|колонк|телевізор|датчик|температур|волог|режим сну",
            request.text.casefold(),
        )
        if not continuous and not explicit_target:
            return "Please name the device and full action; this home conversation does not have that earlier context. No action was attempted."
        try:
            async with asyncio.timeout(self._timeout_s):
                async with self._connect(self._url, max_size=2**20, open_timeout=5) as ws:
                    if json.loads(await ws.recv()).get("type") != "auth_required":
                        raise ConsultFailed("Home Assistant authentication unavailable")
                    await ws.send(json.dumps({"type": "auth", "access_token": self._token}))
                    if json.loads(await ws.recv()).get("type") != "auth_ok":
                        raise ConsultFailed("Home Assistant authentication refused")
                    command = {
                        "id": 1,
                        "type": "assist_pipeline/run",
                        "pipeline": self._pipeline,
                        "start_stage": "intent",
                        "end_stage": "intent",
                        "input": {"text": request.text},
                        "device_id": self._device_id,
                        "timeout": self._timeout_s - 1,
                    }
                    if conversation_id:
                        command["conversation_id"] = conversation_id
                    if not self._is_current(request):
                        return "The request changed while connecting to Home Assistant. No action was attempted."
                    await ws.send(json.dumps(command))
                    output = None
                    async for raw in ws:
                        message = json.loads(raw)
                        if message.get("id") != 1:
                            continue
                        if message.get("type") == "result" and not message.get("success"):
                            raise ConsultFailed("Home Assistant rejected the pipeline request; not retried")
                        event = message.get("event", {})
                        kind, data = event.get("type"), event.get("data", {})
                        if kind == "error":
                            raise ConsultFailed(
                                "Home Assistant pipeline failed; actions may have occurred, not retried"
                            )
                        if kind == "intent-end":
                            output = data["intent_output"]
                        if kind == "run-end":
                            if output is None:
                                raise ConsultFailed("Home Assistant returned no intent result; not retried")
                            if output.get("response", {}).get("response_type") != "error":
                                self._conversation_id = output.get("conversation_id", conversation_id)
                                self._previous_request = request.text.strip()
                            return _answer(output)
        except (TimeoutError, OSError, WebSocketException, ValueError, KeyError, TypeError) as e:
            raise ConsultFailed("Home Assistant result uncertain; no retry or alternate backend was run") from e
        raise ConsultFailed("Home Assistant disconnected; result uncertain, not retried")


def _answer(output: dict[str, Any]) -> str:
    response = output.get("response", {})
    speech = response.get("speech", {}).get("plain", {}).get("speech", "").strip()
    if speech:
        return speech
    if response.get("response_type") == "error":
        return "Home Assistant could not handle the request. No alternate backend was run."
    return "Home Assistant returned no spoken result. Check the home before repeating any action."
