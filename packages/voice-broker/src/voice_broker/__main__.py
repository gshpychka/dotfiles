"""Entry point: `voice-broker --config <file>`."""

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
from .archive import Archive
from .calls import Calls
from .config import Config, Device
from .conversation import Conversation
from .dispatch import Dispatcher, agent_task
from .home_assistant import HomeAssistant
from .live import LiveSession, live_connector
from .openclaw import HistoryUnavailable, OpenClaw
from .protocol import MIC_RATE, ProtocolError, parse_start
from .routing import NaiveRouter, RouteRequest

log = logging.getLogger("voice_broker")

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
        if config.routing is not None and config.routing.strategy != "naive":
            raise ValueError("this branch supports routing.strategy=naive only")
        self._archive = Archive(config.openclaw, config.routing.archive_dir) if config.routing else None
        self._openclaw = OpenClaw(config.openclaw)
        self._devices = {d.address: _DeviceState(d, EchoCanceller(MIC_RATE)) for d in config.devices}
        self._connect = live_connector(AsyncOpenAI(api_key=config.openai_api_key))
        self._calls = Calls(config.calls, config.devices, busy=self._in_conversation)

    def _in_conversation(self, address: str) -> bool:
        current = self._devices[address].current
        return current is not None and not current.done()

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
        opening = self._calls.answer(device.remote_address[0])
        if opening is None:
            log.info("woken by %s", start.wake_word)
        else:
            log.info("answering a call")

        async def recall():
            try:
                recent = await self._openclaw.recent()
            except HistoryUnavailable:
                log.warning("gateway history unavailable; retaining local voice history")
                recent = []
            return recent + (self._archive.recent() if self._archive else [])

        async def agent(request: RouteRequest) -> str:
            return await self._openclaw.consult(agent_task(request))

        dispatcher = None
        if routing := self._config.routing:
            home = HomeAssistant(
                self._config.calls.home_assistant_url,
                self._config.calls.home_assistant_token,
                routing.pipeline,
                routing.devices.get(state.device.name, ""),
                is_current=lambda request: session.request_is_current(request),
            )
            dispatcher = Dispatcher(
                NaiveRouter(), home.consult, agent, is_current=lambda request: session.request_is_current(request)
            )

        async def remember(request: RouteRequest, answer: str) -> None:
            if self._archive and dispatcher:
                if dispatcher.last_route == "openclaw":
                    self._archive.discard(request)
                else:
                    await self._archive.record(request, answer)

        session = LiveSession(
            self._config.live,
            state.device.area,
            self._openclaw.consult,
            recall,
            self._connect,
            opening,
            routed=dispatcher.consult if dispatcher else None,
            device=state.device.name,
            settle_s=routing.settle_s if routing else 0.35,
            remember=remember if self._archive else None,
            persist=self._archive.stage if self._archive else None,
        )
        reason = await Conversation(self._config, state.device.name, device, session, state.aec).run()
        log.info("conversation over: %s", reason)

    async def run(self) -> None:
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
                calls = await self._calls.serve()
                stop = asyncio.Event()
                loop = asyncio.get_running_loop()
                for sig in (signal.SIGINT, signal.SIGTERM):
                    loop.add_signal_handler(sig, stop.set)
                await stop.wait()
                calls.close()
                server.close()
        finally:
            await self._openclaw.aclose()


def main() -> None:
    parser = argparse.ArgumentParser(prog="voice-broker")
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
