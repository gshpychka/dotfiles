"""Entry point: `realtime-voice --config <file>`."""

from __future__ import annotations

import argparse
import asyncio
import hmac
import logging
import signal
from contextvars import ContextVar
from dataclasses import dataclass
from http import HTTPStatus
from pathlib import Path

from openai import AsyncOpenAI
from websockets.asyncio.server import Server, ServerConnection, serve
from websockets.exceptions import ConnectionClosed
from websockets.http11 import Request, Response

from . import config as config_module
from ._aec import EchoCanceller
from .config import Config, Device
from .conversation import Conversation
from .live import LiveSession, live_connector
from .mcp_hub import McpHub
from .protocol import MIC_RATE, Backend, ProtocolError, parse_start
from .realtime import RealtimeSession, realtime_connector
from .session import ModelSession

log = logging.getLogger("realtime_voice")

# The device sends START right after connecting.
_START_TIMEOUT_S = 5

# The device a log record belongs to; every conversation task inherits it.
_device_name: ContextVar[str] = ContextVar("device", default="-")


class _DeviceFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.device = _device_name.get()
        return True


@dataclass
class _DeviceState:
    device: Device
    # Each room has its own echo path.
    aec: EchoCanceller
    # One conversation per device: a new wake word while one is running means
    # the old one is stale (e.g. the device rebooted mid-session).
    current: asyncio.Task[object] | None = None


class Broker:
    def __init__(self, config: Config) -> None:
        self._config = config
        self._hub = McpHub(config.mcp_servers)
        self._devices = {d.address: _DeviceState(d, EchoCanceller(MIC_RATE)) for d in config.devices}
        client = AsyncOpenAI(api_key=config.openai_api_key)
        self._connect_realtime = realtime_connector(client, config.realtime.model)
        self._connect_live = live_connector(client)

    def _authorize(self, connection: ServerConnection, request: Request) -> Response | None:
        if connection.remote_address[0] not in self._devices:
            log.warning("rejected connection from unknown address %s", connection.remote_address)
            return connection.respond(HTTPStatus.FORBIDDEN, "unknown device\n")
        expected = f"Bearer {self._config.device_token}"
        given = request.headers.get("Authorization", "")
        if not hmac.compare_digest(given.encode(), expected.encode()):
            log.warning("rejected connection from %s", connection.remote_address)
            return connection.respond(HTTPStatus.UNAUTHORIZED, "unauthorized\n")
        return None

    async def _handle(self, device: ServerConnection) -> None:
        state = self._devices[device.remote_address[0]]
        _device_name.set(state.device.name)
        if state.current is not None and not state.current.done():
            log.info("new conversation replaces the running one")
            state.current.cancel()
        log.info("conversation from %s", device.remote_address)
        state.current = asyncio.current_task()
        try:
            start = parse_start(await asyncio.wait_for(device.recv(), _START_TIMEOUT_S))
        except (TimeoutError, ProtocolError, ConnectionClosed) as e:
            log.warning("no valid start from %s: %r", device.remote_address, e)
            return
        log.info("woken by %s, %s backend", start.wake_word, start.backend)
        session = self._session(start.backend, state.device.area)
        reason = await Conversation(self._config, state.device.name, device, session, state.aec).run()
        log.info("conversation over: %s", reason)

    def _session(self, backend: Backend, area: str) -> ModelSession:
        match backend:
            case Backend.REALTIME:
                return RealtimeSession(self._config.realtime, area, self._hub, self._connect_realtime)
            case Backend.LIVE:
                return LiveSession(self._config.live, area, self._hub, self._connect_live)

    async def run(self) -> None:
        await self._hub.start()
        try:
            server: Server
            async with serve(
                self._handle,
                self._config.listen_host,
                self._config.listen_port,
                process_request=self._authorize,
                # Audio frames are small; this bounds what an unauthenticated
                # peer can make the broker buffer.
                max_size=64 * 1024,
                ping_interval=10,
                ping_timeout=10,
            ) as server:
                log.info("listening on %s:%d", self._config.listen_host, self._config.listen_port)
                stop = asyncio.Event()
                loop = asyncio.get_running_loop()
                for sig in (signal.SIGINT, signal.SIGTERM):
                    loop.add_signal_handler(sig, stop.set)
                await stop.wait()
                server.close()
        finally:
            await self._hub.close()


def main() -> None:
    parser = argparse.ArgumentParser(prog="realtime-voice")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args()
    logging.basicConfig(level=args.log_level, format="%(levelname)s %(name)s [%(device)s]: %(message)s")
    for handler in logging.getLogger().handlers:
        handler.addFilter(_DeviceFilter())
    # The OpenAI SDK and httpx log every request at INFO.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    asyncio.run(Broker(config_module.load(args.config)).run())


if __name__ == "__main__":
    main()
