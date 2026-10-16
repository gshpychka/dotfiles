"""Durable private outbox -> Gateway chat.inject (history only, no agent run).

No transcript text is logged. Unacknowledged records stay private on disk;
uncertain inject is not retried automatically (chat.inject has no idempotency).
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
import uuid
from pathlib import Path

from websockets.asyncio.client import connect
from websockets.exceptions import WebSocketException

from .config import OpenClaw
from .openclaw import _newest
from .routing import RouteRequest

log = logging.getLogger(__name__)


class Archive:
    def __init__(self, config: OpenClaw, directory: Path, connector=connect) -> None:
        self._config, self._directory, self._connect = config, directory, connector
        self._pending: dict[RouteRequest, Path] = {}

    def stage(self, request: RouteRequest, answer: str) -> None:
        self._directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        name = self._pending.setdefault(request, self._directory / (uuid.uuid4().hex + ".json"))
        text = "Voice backend exchange (already handled; DO NOT execute again): " + json.dumps(
            {
                "request": request.text,
                "answer": answer,
                "area": request.area,
                "device": request.device,
                "conversation_id": request.conversation_id,
            },
            ensure_ascii=False,
        )
        record = {"text": text, "timestamp": time.time(), "status": "pending"}
        temporary = name.with_suffix(".tmp")
        with open(temporary, "w", opener=lambda path, flags: os.open(path, flags, 0o600)) as f:
            json.dump(record, f, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        temporary.replace(name)
        directory_fd = os.open(self._directory, os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)

    def discard(self, request: RouteRequest) -> None:
        name = self._pending.pop(request, None)
        if name is not None:
            name.unlink(missing_ok=True)

    async def record(self, request: RouteRequest, answer: str) -> None:
        self.stage(request, answer)
        name = self._pending.pop(request)
        text = json.loads(name.read_text())["text"]
        # Acknowledged writes are removed; uncertain ones remain for inspection,
        # and recent() includes them so later conversations cannot lose context.
        try:
            async with asyncio.timeout(2):
                await self._inject(text)
            name.unlink()
        except (OSError, TimeoutError, RuntimeError, ValueError, KeyError, WebSocketException) as e:
            log.warning("voice history retained in private outbox: %s", type(e).__name__)

    def recent(self) -> list[tuple[str, str]]:
        if not self._directory.exists():
            return []
        records = []
        for name in self._directory.glob("*.json"):
            try:
                record = json.loads(name.read_text())
                records.append((record["timestamp"], record["text"]))
            except (OSError, ValueError, KeyError, TypeError):
                log.warning("unreadable voice history record; retained for inspection")
        turns = [
            ("assistant", text)
            for timestamp, text in sorted(records)
            if timestamp > time.time() - self._config.history.max_age_s
        ]
        return _newest(turns, self._config.history.max_chars)

    async def _inject(self, text: str) -> None:
        url = self._config.url.replace("https://", "wss://").replace("http://", "ws://")
        async with self._connect(url, open_timeout=1, max_size=2**20) as ws:
            challenge = json.loads(await ws.recv())
            if challenge.get("event") != "connect.challenge":
                raise RuntimeError("missing gateway challenge")
            await ws.send(
                json.dumps(
                    {
                        "type": "req",
                        "id": "connect",
                        "method": "connect",
                        "params": {
                            "minProtocol": 3,
                            "maxProtocol": 3,
                            "client": {
                                "id": "gateway-client",
                                "version": "voice-broker",
                                "platform": "linux",
                                "mode": "backend",
                            },
                            "role": "operator",
                            "scopes": ["operator.admin"],
                            "auth": {"token": self._config.token},
                        },
                    }
                )
            )
            await self._response(ws, "connect")
            await ws.send(
                json.dumps(
                    {
                        "type": "req",
                        "id": "archive",
                        "method": "chat.inject",
                        "params": {
                            "sessionKey": self._config.session_key,
                            "message": text,
                            "label": "Voice backend",
                        },
                    }
                )
            )
            await self._response(ws, "archive")

    @staticmethod
    async def _response(ws, request_id: str) -> None:
        async for raw in ws:
            result = json.loads(raw)
            if result.get("type") == "res" and result.get("id") == request_id:
                if not result.get("ok"):
                    raise RuntimeError("gateway history append refused")
                return
        raise RuntimeError("gateway history connection closed")
