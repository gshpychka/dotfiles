"""Entry point: `realtime-voice --config <file>`."""

from __future__ import annotations

import argparse
import asyncio
import hmac
import logging
import signal
from http import HTTPStatus
from pathlib import Path

from openai import AsyncOpenAI
from websockets.asyncio.server import Server, ServerConnection, serve
from websockets.http11 import Request, Response

from . import config as config_module
from .config import Config
from ._aec import EchoCanceller
from .conversation import Conversation, openai_connector
from .mcp_hub import McpHub
from .protocol import MIC_RATE

log = logging.getLogger("realtime_voice")


class Broker:
    def __init__(self, config: Config) -> None:
        self._config = config
        self._hub = McpHub(config.mcp_servers)
        self._aec = EchoCanceller(MIC_RATE)
        self._connect = openai_connector(AsyncOpenAI(api_key=config.openai_api_key), config.model)
        # One conversation at a time: a new wake word while one is running
        # means the old one is stale (e.g. the device rebooted mid-session).
        self._current: asyncio.Task[object] | None = None

    def _authorize(self, connection: ServerConnection, request: Request) -> Response | None:
        expected = f"Bearer {self._config.device_token}"
        given = request.headers.get("Authorization", "")
        if not hmac.compare_digest(given.encode(), expected.encode()):
            log.warning("rejected connection from %s", connection.remote_address)
            return connection.respond(HTTPStatus.UNAUTHORIZED, "unauthorized\n")
        return None

    async def _handle(self, device: ServerConnection) -> None:
        if self._current is not None and not self._current.done():
            log.info("new conversation replaces the running one")
            self._current.cancel()
        log.info("conversation from %s", device.remote_address)
        self._current = asyncio.current_task()
        reason = await Conversation(self._config, self._hub, device, self._connect, self._aec).run()
        log.info("conversation over: %s", reason)

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
    logging.basicConfig(level=args.log_level, format="%(levelname)s %(name)s: %(message)s")
    # The OpenAI SDK and httpx log every request at INFO.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    asyncio.run(Broker(config_module.load(args.config)).run())


if __name__ == "__main__":
    main()
