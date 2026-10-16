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
from .calls import Calls
from .config import Config, Device
from .conversation import Conversation
from .home_assistant import HomeAssistant
from .live import LiveSession, Routed, live_connector
from .openclaw import OpenClaw
from .protocol import MIC_RATE, ProtocolError, parse_start
from .routing import DecisionsRouter

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
        self._openclaw = OpenClaw(config.openclaw)
        self._devices = {d.address: _DeviceState(d, EchoCanceller(MIC_RATE)) for d in config.devices}
        openai = AsyncOpenAI(api_key=config.openai_api_key)
        self._connect = live_connector(openai)
        self._router = (
            DecisionsRouter(openai, config.routing.model, config.routing.timeout_s) if config.routing else None
        )
        self._calls = Calls(config.calls, config.devices, busy=self._in_conversation)

    def _routed(self, device: Device) -> Routed | None:
        """Routing for a conversation at `device`, with its own Home Assistant device."""
        routing = self._config.routing
        if routing is None:
            return None
        assert self._router is not None
        # config.load requires a device ID of every device while routing is on.
        assert device.home_assistant_device_id is not None
        home = HomeAssistant(
            self._config.calls.home_assistant_url,
            self._config.calls.home_assistant_token,
            routing.pipeline,
            device.home_assistant_device_id,
        )
        return Routed(self._router.route, home.converse, routing.pending_question_s, routing.settle_s)

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
        session = LiveSession(
            self._config.live,
            state.device.area,
            self._openclaw.consult,
            self._openclaw.recent,
            self._connect,
            opening,
            # A call answers the agent, so the reply is the agent's whatever it says.
            self._routed(state.device) if opening is None else None,
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
