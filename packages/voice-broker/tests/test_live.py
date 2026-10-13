"""Delegation and history: a scripted Live connection, a recording host and a fake agent."""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from types import SimpleNamespace

import numpy as np
from voice_broker.config import Live
from voice_broker.live import LiveSession
from voice_broker.openclaw import ConsultFailed, HistoryUnavailable, Turn
from voice_broker.protocol import Phase


class Host:
    assistant_audible = False

    def __init__(self) -> None:
        self.phases: list[Phase] = []

    def play(self, samples: np.ndarray) -> None:
        pass

    async def set_phase(self, phase: Phase) -> None:
        self.phases.append(phase)

    def mark_activity(self) -> None:
        pass


class Connection:
    def __init__(self) -> None:
        self.events: asyncio.Queue[SimpleNamespace | None] = asyncio.Queue()
        self.commentary: list[dict] = []
        self.started: list[dict] = []
        self.session = SimpleNamespace(
            start=self._start,
            input_audio=SimpleNamespace(append=self._ignore),
            commentary=SimpleNamespace(append=self._comment),
        )

    async def _start(self, session: dict) -> None:
        self.started.append(session)
        await self.events.put(SimpleNamespace(type="session.started"))

    async def _ignore(self, **kwargs) -> None:
        pass

    async def _comment(self, **kwargs) -> None:
        self.commentary.append(kwargs)

    def user(self, text: str) -> None:
        self.events.put_nowait(SimpleNamespace(type="session.input_transcript.delta", delta=text))

    def delegate(self, delegation_id: str) -> None:
        self.events.put_nowait(
            SimpleNamespace(
                type="session.delegation.created", delegation=SimpleNamespace(id=delegation_id, target="client")
            )
        )

    def __aiter__(self):
        return self

    async def __anext__(self):
        event = await self.events.get()
        if event is None:
            raise StopAsyncIteration
        return event


async def nothing_recent() -> list[Turn]:
    return []


async def no_consult(task: str) -> str:
    raise AssertionError("no consult expected")


async def run(script, consult=no_consult, recall=nothing_recent) -> tuple[Connection, Host]:
    """Runs a session until `script(conn, session)` returns and its delegated work settles."""
    conn = Connection()
    host = Host()

    @asynccontextmanager
    async def connect():
        yield conn

    session = LiveSession(Live(model="gpt-live-1", voice="marin", instructions=""), "Kitchen", consult, recall, connect)
    async with session.open(host):
        receiving = asyncio.create_task(session.receive())
        await script(conn, session)
        while session.busy:
            await asyncio.sleep(0.01)
        await conn.events.put(None)
        await receiving
    return conn, host


async def settle() -> None:
    for _ in range(5):
        await asyncio.sleep(0)


def test_a_new_delegation_supersedes_the_running_consult():
    tasks: list[str] = []
    cancelled = asyncio.Event()

    async def consult(task: str) -> str:
        tasks.append(task)
        if len(tasks) == 1:
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                cancelled.set()
                raise
        return "Done."

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn off the lights.")
        conn.delegate("dlg_1")
        await settle()
        conn.user(" And the fan.")
        conn.delegate("dlg_2")
        await settle()

    conn, host = asyncio.run(run(script, consult))

    assert cancelled.is_set()
    # The second task carries the first request too: its consult never answered.
    assert "user: Turn off the lights. And the fan." in tasks[1]
    assert conn.commentary == [{"content": "Done.", "delegation_id": "dlg_2"}]
    assert host.phases[-1] == Phase.LISTENING


def test_a_delegation_with_no_user_speech_asks_for_a_repeat():
    async def script(conn: Connection, session: LiveSession) -> None:
        conn.delegate("dlg_1")
        await settle()

    conn, _ = asyncio.run(run(script))

    (comment,) = conn.commentary
    assert "repeat" in comment["content"] and comment["delegation_id"] == "dlg_1"


def test_a_failed_consult_is_reported_and_its_request_carried_forward():
    tasks: list[str] = []

    async def consult(task: str) -> str:
        tasks.append(task)
        if len(tasks) == 1:
            raise ConsultFailed("gateway down")
        return "Done."

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn off the lights.")
        conn.delegate("dlg_1")
        await settle()
        while session.busy:
            await asyncio.sleep(0.01)
        conn.user(" Try again.")
        conn.delegate("dlg_2")
        await settle()

    conn, _ = asyncio.run(run(script, consult))

    assert "gateway down" in conn.commentary[0]["content"]
    assert "user: Turn off the lights. Try again." in tasks[1]


def test_long_answers_arrive_in_appends_within_the_limit():
    answer = " ".join(f"word{i}" for i in range(300))

    async def consult(task: str) -> str:
        return answer

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Read me everything.")
        conn.delegate("dlg_1")
        await settle()

    conn, _ = asyncio.run(run(script, consult))

    contents = [c["content"] for c in conn.commentary]
    assert len(contents) > 1
    assert all(len(c.encode()) <= 500 for c in contents)
    assert " ".join(contents) == answer


async def no_script(conn: Connection, session: LiveSession) -> None:
    pass


def test_the_recent_conversation_leads_the_session():
    async def recall() -> list[Turn]:
        return [("user", "Remind me to call mom."), ("assistant", "Noted, at six.")]

    conn, _ = asyncio.run(run(no_script, recall=recall))

    (started,) = conn.started
    lead, *items = started["input"]
    assert lead["role"] == "developer" and "spoken conversation" in lead["content"][0]["text"]
    assert items == [
        {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Remind me to call mom."}]},
        {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Noted, at six."}]},
    ]


def test_no_recent_conversation_means_no_history():
    conn, _ = asyncio.run(run(no_script))

    (started,) = conn.started
    assert "input" not in started


def test_an_unreadable_conversation_does_not_stop_the_session():
    async def recall() -> list[Turn]:
        raise HistoryUnavailable("gateway down")

    conn, _ = asyncio.run(run(no_script, recall=recall))

    (started,) = conn.started
    assert "input" not in started


def test_the_history_keeps_its_newest_within_lives_cap():
    async def recall() -> list[Turn]:
        return [("user", f"message {i}") for i in range(200)]

    conn, _ = asyncio.run(run(no_script, recall=recall))

    (started,) = conn.started
    items = started["input"]
    assert len(items) == 128
    assert items[-1]["content"][0]["text"] == "message 199"
