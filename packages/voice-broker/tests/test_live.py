"""Delegation and history: a scripted Live connection, a recording host and a fake agent."""

from __future__ import annotations

import asyncio
import base64
from contextlib import asynccontextmanager
from types import SimpleNamespace

import numpy as np
import pytest
from voice_broker.config import Live
from voice_broker.live import LiveSession, MicOverflow
from voice_broker.openclaw import ConsultFailed, HistoryUnavailable, Turn
from voice_broker.protocol import MIC_RATE, SPEAKER_RATE, Phase


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
        # Appended input audio, decoded to SPEAKER_RATE samples, in order.
        self.audio: list[np.ndarray] = []
        self.session = SimpleNamespace(
            start=self._start,
            input_audio=SimpleNamespace(append=self._audio),
            commentary=SimpleNamespace(append=self._comment),
        )

    async def _start(self, session: dict) -> None:
        self.started.append(session)
        await self.events.put(SimpleNamespace(type="session.started"))

    async def _audio(self, audio: str) -> None:
        self.audio.append(np.frombuffer(base64.b64decode(audio), dtype="<i2"))

    async def _comment(self, **kwargs) -> None:
        self.commentary.append(kwargs)

    # The Live timeline, in ms: each fragment and delegation lands after the last.
    clock_ms = 0

    def user(self, text: str, start_ms: int | None = None) -> None:
        self.clock_ms += 100
        start = self.clock_ms if start_ms is None else start_ms
        self.events.put_nowait(
            SimpleNamespace(type="session.input_transcript.delta", delta=text, start_ms=start, end_ms=start + 100)
        )

    def delegate(self, delegation_id: str) -> None:
        self.clock_ms += 100
        self.events.put_nowait(
            SimpleNamespace(
                type="session.delegation.created",
                delegation=SimpleNamespace(id=delegation_id, target="client"),
                offset_ms=self.clock_ms,
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


async def run(script, consult=no_consult, recall=nothing_recent, opening=None) -> tuple[Connection, Host]:
    """Runs a session until `script(conn, session)` returns and its delegated work settles."""
    conn = Connection()
    host = Host()

    @asynccontextmanager
    async def connect():
        yield conn

    session = LiveSession(
        Live(model="gpt-live-1", voice="marin", instructions=""), "Kitchen", consult, recall, connect, opening
    )
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


def test_a_delegation_during_a_consult_waits_for_it():
    tasks: list[str] = []
    release = asyncio.Event()

    async def consult(task: str) -> str:
        tasks.append(task)
        if len(tasks) == 1:
            await release.wait()
        return f"Done {len(tasks)}."

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn off the lights.")
        conn.delegate("dlg_1")
        await settle()
        conn.user(" And the fan.")
        conn.delegate("dlg_2")
        await settle()
        assert len(tasks) == 1
        release.set()

    conn, host = asyncio.run(run(script, consult))

    # The first consult answered at the newest delegation; what was said since got its own.
    assert "user: Turn off the lights." in tasks[0] and "fan" not in tasks[0]
    assert "user: And the fan." in tasks[1] and "lights" not in tasks[1]
    assert conn.commentary == [
        {"content": "Done 1.", "delegation_id": "dlg_2"},
        {"content": "Done 2.", "delegation_id": "dlg_2"},
    ]
    assert host.phases[-1] == Phase.LISTENING


def test_a_delegation_without_new_speech_takes_the_running_consults_answer():
    tasks: list[str] = []
    release = asyncio.Event()

    async def consult(task: str) -> str:
        tasks.append(task)
        await release.wait()
        return "Done."

    async def script(conn: Connection, session: LiveSession) -> None:
        conn.user("Turn off the lights.")
        conn.delegate("dlg_1")
        await settle()
        conn.delegate("dlg_2")
        await settle()
        release.set()

    conn, _ = asyncio.run(run(script, consult))

    assert len(tasks) == 1
    assert conn.commentary == [{"content": "Done.", "delegation_id": "dlg_2"}]


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


def test_the_session_starts_with_the_instructions_then_the_speakers_place():
    conn = Connection()

    @asynccontextmanager
    async def connect():
        yield conn

    instructions = "Who you are:\n- **Name:** Calcifer\n\nBackchannel policy: Use moderate backchannels.\n"
    session = LiveSession(
        Live(model="gpt-live-1", voice="marin", instructions=instructions),
        "Kitchen",
        no_consult,
        nothing_recent,
        connect,
        None,
    )

    async def opened() -> None:
        async with session.open(Host()):
            pass

    asyncio.run(opened())

    (started,) = conn.started
    assert started["instructions"] == (
        "Who you are:\n- **Name:** Calcifer\n\nBackchannel policy: Use moderate backchannels.\n\n"
        "This speaker is in the Kitchen. A request that names no place is about the Kitchen.\n"
    )
    assert started["model"] == "gpt-live-1"
    assert started["audio"]["output"] == {"voice": "marin"}
    assert started["delegation"] == {"type": "client"}


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


def block(level: int, ms: int = 10) -> np.ndarray:
    """`ms` of mic audio at one level."""
    return np.full(MIC_RATE * ms // 1000, level, dtype=np.int16)


async def session_with(conn: Connection) -> LiveSession:
    @asynccontextmanager
    async def connect():
        yield conn

    return LiveSession(
        Live(model="gpt-live-1", voice="marin", instructions=""), "Kitchen", no_consult, nothing_recent, connect
    )


def test_mic_audio_heard_before_the_session_opens_reaches_it_first():
    async def main() -> Connection:
        conn = Connection()
        session = await session_with(conn)
        await session.on_mic(block(1000, ms=200))
        await session.on_mic(block(2000, ms=200))
        async with session.open(Host()):
            await session.on_mic(block(-1000, ms=200))
            await session._mic.drained()
        return conn

    conn = asyncio.run(main())

    # The resampler lags a few milliseconds, so each level is read well inside its stretch.
    audio = np.concatenate(conn.audio)
    assert len(audio) > SPEAKER_RATE * 550 // 1000
    stretch = SPEAKER_RATE * 200 // 1000
    levels = [float(np.median(audio[i * stretch + 1000 : i * stretch + 3000])) for i in range(3)]
    assert np.allclose(levels, [1000, 2000, -1000], atol=5)


def test_held_audio_past_fifteen_seconds_ends_the_conversation_instead_of_losing_its_start():
    async def main() -> tuple[Connection, int, str]:
        conn = Connection()
        session = await session_with(conn)
        blocks = 0
        try:
            for _ in range(200):
                await session.on_mic(block(1000, ms=100))
                blocks += 1
        except MicOverflow as e:
            error = str(e)
        else:
            raise AssertionError("no overflow")
        with pytest.raises(MicOverflow):
            await session.on_mic(block(1000, ms=100))
        async with session.open(Host()):
            pass
        return conn, blocks, error

    conn, blocks, error = asyncio.run(main())

    # Nothing held was dropped to make room, and the session never heard a trimmed start.
    assert 140 <= blocks <= 150
    assert "more than 15 s" in error
    assert conn.audio == []


def test_a_call_opens_with_the_agents_words():
    conn, _ = asyncio.run(run(no_script, opening="The oven has been on for two hours."))

    (started,) = conn.started
    (opening,) = started["input"]
    assert opening["role"] == "developer"
    text = opening["content"][0]["text"]
    assert "The oven has been on for two hours." in text and "Delegate the user's response" in text


def test_the_opening_follows_the_history_within_lives_cap():
    async def recall() -> list[Turn]:
        return [("user", f"message {i}") for i in range(200)]

    conn, _ = asyncio.run(run(no_script, recall=recall, opening="Dinner is ready."))

    (started,) = conn.started
    items = started["input"]
    assert len(items) == 128
    assert items[0]["role"] == "developer" and items[-2]["content"][0]["text"] == "message 199"
    assert items[-1]["role"] == "developer" and "Dinner is ready." in items[-1]["content"][0]["text"]
