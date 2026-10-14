"""Calls: the agent's request, the ring through Home Assistant, and the speaker's answer."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path

import httpx2
import pytest
from voice_broker.calls import CallFailed, Calls
from voice_broker.config import Calls as CallsConfig
from voice_broker.config import Device

ROOM = Device("room-assistant", "192.168.1.54", "Room", "esphome.home_assistant_voice_0914cc_start_conversation")


def config(tmp_path: Path) -> CallsConfig:
    return CallsConfig(
        socket=tmp_path / "call.sock", home_assistant_url="http://ha.test", home_assistant_token="ha-token"
    )


def rings_ok(request: httpx2.Request) -> httpx2.Response:
    return httpx2.Response(200, json=[])


def calls(tmp_path: Path, handler=rings_ok, busy: bool = False, answer_timeout_s: float = 1.0) -> Calls:
    return Calls(
        config(tmp_path),
        [ROOM],
        busy=lambda address: busy,
        http_client=httpx2.AsyncClient(transport=httpx2.MockTransport(handler)),
        answer_timeout_s=answer_timeout_s,
    )


def test_a_call_rings_the_speaker_and_returns_once_it_answers(tmp_path: Path):
    rings: list[httpx2.Request] = []

    def ha(request: httpx2.Request) -> httpx2.Response:
        rings.append(request)
        return httpx2.Response(200, json=[])

    async def main() -> None:
        placed = calls(tmp_path, ha)
        placing = asyncio.create_task(placed.place("Room", "The oven is on."))
        while not rings:
            await asyncio.sleep(0.01)
        assert not placing.done()
        assert placed.answer(ROOM.address) == "The oven is on."
        await placing
        # Answered: a later conversation from the speaker is an ordinary one.
        assert placed.answer(ROOM.address) is None

    asyncio.run(main())
    (ring,) = rings
    assert ring.method == "POST"
    assert str(ring.url) == "http://ha.test/api/services/esphome/home_assistant_voice_0914cc_start_conversation"
    assert ring.headers["authorization"] == "Bearer ha-token"


def test_a_speaker_that_does_not_pick_up_fails_the_call(tmp_path: Path):
    with pytest.raises(CallFailed, match="did not answer"):
        asyncio.run(calls(tmp_path, answer_timeout_s=0.05).place("Room", "Hello?"))


def test_a_speaker_in_a_conversation_is_not_rung(tmp_path: Path):
    def ha(request: httpx2.Request) -> httpx2.Response:
        raise AssertionError("no ring expected")

    with pytest.raises(CallFailed, match="in a conversation"):
        asyncio.run(calls(tmp_path, ha, busy=True).place("Room", "Hello?"))


def test_an_unknown_area_fails_naming_the_known_ones(tmp_path: Path):
    with pytest.raises(CallFailed, match="Room"):
        asyncio.run(calls(tmp_path).place("Garage", "Hello?"))


def test_home_assistant_failing_fails_the_call(tmp_path: Path):
    def ha(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(500, text="boom")

    with pytest.raises(CallFailed, match="Home Assistant"):
        asyncio.run(calls(tmp_path, ha).place("Room", "Hello?"))


def test_the_socket_takes_a_request_and_reports_the_outcome(tmp_path: Path):
    async def request(path: Path, body: dict) -> dict:
        reader, writer = await asyncio.open_unix_connection(path)
        writer.write(json.dumps(body).encode() + b"\n")
        await writer.drain()
        reply = json.loads(await reader.readline())
        writer.close()
        return reply

    async def main() -> tuple[dict, dict, int]:
        placed = calls(tmp_path, answer_timeout_s=0.05)
        server = await placed.serve()
        path = config(tmp_path).socket
        mode = path.stat().st_mode & 0o777
        started = asyncio.create_task(request(path, {"area": "Room", "opening": "The oven is on."}))
        while placed.answer(ROOM.address) is None:
            await asyncio.sleep(0.01)
        failed = await request(path, {"area": "Garage", "opening": "Hello?"})
        server.close()
        return await started, failed, mode

    started, failed, mode = asyncio.run(main())
    assert started == {"status": "started"}
    assert failed["status"] == "failed" and "Garage" in failed["reason"]
    assert mode == 0o660
