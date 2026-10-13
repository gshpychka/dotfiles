"""Calls: conversations the agent opens on a speaker, to tell the user something and hear the reply.

The agent asks over a Unix socket with one JSON line, {"area": ..., "opening": ...}.
The broker rings the speaker through its Home Assistant action, which makes the
device open a conversation the way a wake word does, and answers with one JSON
line: {"status": "started"} once the speaker has connected, or
{"status": "failed", "reason": ...}. What the user replies reaches the agent as
a consult, like anything else said at a speaker.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import socket
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import httpx2

from .config import Calls as CallsConfig
from .config import Device

log = logging.getLogger(__name__)

# From the ring to the device's START.
_ANSWER_TIMEOUT_S = 15.0
# One Home Assistant action call.
_RING_TIMEOUT_S = 10.0
# The socket's group is the agent's way in.
_SOCKET_MODE = 0o660


class CallFailed(Exception):
    """The speaker did not come up for the call."""


@dataclass
class _Ringing:
    opening: str
    answered: asyncio.Future[None]


class Calls:
    """The agent's calls, from request to the speaker's answer."""

    def __init__(
        self,
        config: CallsConfig,
        devices: list[Device],
        busy: Callable[[str], bool],
        http_client: httpx2.AsyncClient | None = None,
        answer_timeout_s: float = _ANSWER_TIMEOUT_S,
    ) -> None:
        self._config = config
        self._by_area = {device.area: device for device in devices}
        # Whether the device at an address is in a conversation.
        self._busy = busy
        self._http = http_client or httpx2.AsyncClient()
        self._answer_timeout_s = answer_timeout_s
        # By device address.
        self._ringing: dict[str, _Ringing] = {}

    async def place(self, area: str, opening: str) -> None:
        """Rings the speaker in `area` for `opening` and returns once it has answered; raises CallFailed."""
        device = self._by_area.get(area)
        if device is None:
            raise CallFailed(f"no speaker in {area!r}; the areas are {', '.join(sorted(self._by_area))}")
        if device.address in self._ringing:
            raise CallFailed(f"the {area} speaker is already ringing")
        if self._busy(device.address):
            raise CallFailed(f"the {area} speaker is in a conversation")
        ringing = _Ringing(opening, asyncio.get_running_loop().create_future())
        self._ringing[device.address] = ringing
        try:
            await self._ring(device)
            async with asyncio.timeout(self._answer_timeout_s):
                await ringing.answered
        except TimeoutError:
            raise CallFailed(f"the {area} speaker did not answer") from None
        finally:
            del self._ringing[device.address]
        log.info("call to the %s answered", area)

    def answer(self, address: str) -> str | None:
        """The opening of the call that a conversation from `address` answers, while one is ringing there."""
        ringing = self._ringing.get(address)
        if ringing is None:
            return None
        if not ringing.answered.done():
            ringing.answered.set_result(None)
        return ringing.opening

    async def _ring(self, device: Device) -> None:
        domain, _, action = device.call_action.partition(".")
        try:
            response = await self._http.post(
                f"{self._config.home_assistant_url}/api/services/{domain}/{action}",
                headers={"Authorization": f"Bearer {self._config.home_assistant_token}"},
                json={},
                timeout=_RING_TIMEOUT_S,
            )
            response.raise_for_status()
        except httpx2.HTTPError as e:
            raise CallFailed(f"Home Assistant could not ring {device.name}: {e!r}") from e

    async def serve(self) -> asyncio.AbstractServer:
        """Listens for the agent's requests on the configured socket."""
        path = self._config.socket
        path.unlink(missing_ok=True)
        server = await asyncio.start_unix_server(self._serve_one, path=path)
        path.chmod(_SOCKET_MODE)
        return server

    async def _serve_one(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            request = json.loads(await reader.readline())
            await self.place(str(request["area"]), str(request["opening"]))
            reply = {"status": "started"}
        except CallFailed as e:
            log.warning("call failed: %s", e)
            reply = {"status": "failed", "reason": str(e)}
        except (KeyError, TypeError, ValueError) as e:
            reply = {"status": "failed", "reason": f"bad request: {e!r}"}
        writer.write(json.dumps(reply).encode() + b"\n")
        await writer.drain()
        writer.close()


def main() -> None:
    """`voice-broker-call`: the agent's side of a call."""
    parser = argparse.ArgumentParser(
        prog="voice-broker-call",
        description="Opens a conversation on a speaker: it says the opening in its own words and listens for the reply.",
    )
    parser.add_argument("--socket", type=Path, required=True, help="the broker's call socket")
    parser.add_argument("area", help="the speaker's area")
    parser.add_argument("opening", help="what the speaker tells the user")
    args = parser.parse_args()
    try:
        with socket.socket(socket.AF_UNIX) as sock:
            sock.connect(str(args.socket))
            sock.sendall(json.dumps({"area": args.area, "opening": args.opening}).encode() + b"\n")
            reply = json.loads(sock.makefile().readline())
    except OSError as e:
        reply = {"status": "failed", "reason": f"the broker is not taking calls: {e}"}
    if reply["status"] == "started":
        print("started")
        return
    print(f"failed: {reply['reason']}")
    sys.exit(1)
