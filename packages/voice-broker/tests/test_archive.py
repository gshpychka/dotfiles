import asyncio
import stat
from contextlib import asynccontextmanager

from test_home_assistant import Socket

from voice_broker.archive import Archive
from voice_broker.routing import RouteRequest


def test_gateway_history_injection_does_not_start_agent(make_config, tmp_path):
    sockets = []

    @asynccontextmanager
    async def connect(*args, **kwargs):
        ws = Socket(
            [
                {"type": "event", "event": "connect.challenge"},
                {"type": "res", "id": "connect", "ok": True},
                {"type": "res", "id": "archive", "ok": True},
            ]
        )
        sockets.append(ws)
        yield ws

    archive = Archive(make_config().openclaw, tmp_path / "outbox", connect)
    asyncio.run(archive.record(RouteRequest("Temperature?", (), "Room", "device", "voice"), "22 degrees."))
    assert sockets[0].sent[1]["method"] == "chat.inject"
    assert "Temperature?" in sockets[0].sent[1]["params"]["message"]
    assert list((tmp_path / "outbox").glob("*.json")) == []


def test_uncertain_history_delivery_preserves_private_outbox_without_retry(make_config, tmp_path):
    calls = []

    @asynccontextmanager
    async def connect(*args, **kwargs):
        calls.append(1)
        raise OSError("unavailable")
        yield

    archive = Archive(make_config().openclaw, tmp_path / "outbox", connect)
    asyncio.run(archive.record(RouteRequest("Temperature?", (), "Room", "d", "v"), "22."))
    (name,) = (tmp_path / "outbox").glob("*.json")
    assert stat.S_IMODE(name.stat().st_mode) == 0o600
    assert len(calls) == 1 and "Temperature?" in archive.recent()[0][1]
