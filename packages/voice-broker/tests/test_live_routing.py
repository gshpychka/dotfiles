"""No partial-delta execution; delayed delivery, ordering, corrections and failures."""

import asyncio
from contextlib import asynccontextmanager
from types import SimpleNamespace

import pytest
from test_live import Connection, Host, no_consult, nothing_recent

from voice_broker.config import Live
from voice_broker.live import LiveSession
from voice_broker.openclaw import ConsultFailed


async def scenario(script, fail=False):
    conn, host, requests = Connection(), Host(), []

    @asynccontextmanager
    async def connect():
        yield conn

    async def routed(req):
        requests.append(req)
        if fail:
            raise ConsultFailed("uncertain")
        return "Done."

    session = LiveSession(
        Live("gpt-live-1", "marin", ""),
        "Room",
        no_consult,
        nothing_recent,
        connect,
        routed=routed,
        device="room",
        settle_s=0.1,
    )
    async with session.open(host):
        receive = asyncio.create_task(session.receive())
        await script(conn, session, requests)
        await asyncio.sleep(0.25)
        while session.busy:
            await asyncio.sleep(0.01)
        conn.events.put_nowait(None)
        await receive
    return conn, requests


def user(conn, text, end=1000):
    conn.events.put_nowait(
        SimpleNamespace(type="session.input_transcript.delta", delta=text, start_ms=end - 100, end_ms=end)
    )


def delegate(conn, ident="d1", offset=1200):
    conn.events.put_nowait(
        SimpleNamespace(
            type="session.delegation.created",
            offset_ms=offset,
            delegation=SimpleNamespace(id=ident, target="NOT_A_ROUTE"),
        )
    )


def test_deltas_alone_never_execute():
    async def script(c, s, requests):
        user(c, "Turn off the lights.")
        await asyncio.sleep(0.2)
        assert not requests

    _, requests = asyncio.run(scenario(script))
    assert requests == []


def test_delegation_before_delayed_transcript_waits_for_full_text():
    async def script(c, s, requests):
        delegate(c)
        await asyncio.sleep(0.04)
        user(c, "Turn off the")
        await asyncio.sleep(0.04)
        assert not requests
        user(c, " lights.", end=1100)

    _, requests = asyncio.run(scenario(script))
    assert [r.text for r in requests] == ["Turn off the lights."]
    assert requests[0].area == "Room" and requests[0].device == "room" and requests[0].conversation_id


@pytest.mark.parametrize(
    "text,end,offset",
    [("Turn off the", 1000, 1200), ("Turn off lights.", 1300, 1200), ("Turn off lights.", 1000, None)],
)
def test_uncorrelated_or_unfinished_input_clarifies(text, end, offset):
    async def script(c, s, requests):
        user(c, text, end)
        delegate(c, offset=offset)

    conn, requests = asyncio.run(scenario(script))
    assert requests == [] and "not complete" in conn.commentary[0]["content"]


def test_duplicate_delegation_and_failure_do_not_replay_action():
    async def script(c, s, requests):
        user(c, "Turn off lights.")
        delegate(c)
        await asyncio.sleep(0.15)
        delegate(c)
        delegate(c, "d2")

    conn, requests = asyncio.run(scenario(script, fail=True))
    assert len(requests) == 1 and "uncertain" in conn.commentary[0]["content"]


def test_correction_after_delegation_without_new_delegation_does_not_execute():
    async def script(c, s, requests):
        user(c, "Turn off lights.")
        delegate(c)
        await asyncio.sleep(0.04)
        user(c, " No, leave them on.", end=1500)

    _, requests = asyncio.run(scenario(script))
    assert not requests


def test_rejected_partial_is_context_not_reexecuted_with_repeat():
    async def script(c, s, requests):
        user(c, "Turn off the")
        delegate(c)
        await asyncio.sleep(0.15)
        user(c, "Leave the lights on.", end=2000)
        delegate(c, "d2", offset=2200)

    _, requests = asyncio.run(scenario(script))
    assert len(requests) == 1 and requests[0].text == "Leave the lights on."
    assert any("Turn off the" in text for _, text in requests[0].context)
