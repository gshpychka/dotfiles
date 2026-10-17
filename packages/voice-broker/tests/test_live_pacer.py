"""The mic pacer: a startup backlog reaches Live in order, paced, bounded, on a fake clock (no real waiting)."""

from __future__ import annotations

import asyncio
import bisect
import heapq
import itertools
import time
from contextlib import asynccontextmanager

import numpy as np
import pytest
from test_conversation import ScriptedLive, SimDevice
from test_live import Connection, Host, block, nothing_recent, session_with
from test_parallel import Conn, Ears, told
from voice_broker import live
from voice_broker._aec import EchoCanceller
from voice_broker.assist import Outcome
from voice_broker.config import Live
from voice_broker.conversation import Conversation, EndReason
from voice_broker.live import (
    _BACKLOG_MAX_SAMPLES,
    _CATCH_UP_SPEED,
    _PACE_AHEAD_S,
    LiveSession,
    MicOverflow,
    Parallel,
    _MicPacer,
)
from voice_broker.protocol import MIC_RATE, SPEAKER_RATE, ControlType

RATE = SPEAKER_RATE
BLOCK_S = 0.02


class FakeClock:
    """Time moves only when every task is waiting on it: the earliest sleeper wakes next."""

    def __init__(self) -> None:
        self.t = 0.0
        self._sleepers: list[tuple[float, int, asyncio.Future[None]]] = []
        self._seq = itertools.count()

    def now(self) -> float:
        return self.t

    async def sleep(self, seconds: float) -> None:
        fut = asyncio.get_running_loop().create_future()
        heapq.heappush(self._sleepers, (self.t + max(seconds, 0.0), next(self._seq), fut))
        await fut

    async def run_until(self, end: float) -> None:
        while True:
            for _ in range(20):
                await asyncio.sleep(0)
            while self._sleepers and self._sleepers[0][2].done():
                heapq.heappop(self._sleepers)
            if not self._sleepers or self._sleepers[0][0] > end:
                self.t = max(self.t, end)
                for _ in range(20):
                    await asyncio.sleep(0)
                return
            deadline, _, fut = heapq.heappop(self._sleepers)
            self.t = max(self.t, deadline)
            fut.set_result(None)


class Ramp:
    """Consecutive blocks of distinct, increasing samples, so order and loss show in the output."""

    def __init__(self) -> None:
        self._next = 0

    def take(self, seconds: float) -> np.ndarray:
        n = round(RATE * seconds)
        out = (np.arange(self._next, self._next + n) % 30000).astype(np.int16)
        self._next += n
        return out


class Recorder:
    def __init__(self, clock: FakeClock, stall: dict[int, float] | None = None) -> None:
        self.clock = clock
        self.sends: list[tuple[float, int]] = []
        self.audio: list[np.ndarray] = []
        self._stall = stall or {}

    async def __call__(self, samples: np.ndarray) -> None:
        if (seconds := self._stall.pop(len(self.sends), None)) is not None:
            await self.clock.sleep(seconds)
        self.sends.append((self.clock.now(), len(samples)))
        self.audio.append(samples.copy())


def pacer(clock: FakeClock) -> _MicPacer:
    return _MicPacer(RATE, _BACKLOG_MAX_SAMPLES, clock=clock.now, sleep=clock.sleep)


async def speak(p: _MicPacer, clock: FakeClock, ramp: Ramp, seconds: float, put: list[np.ndarray]) -> None:
    """The mic: one block every BLOCK_S of fake time."""
    for _ in range(round(seconds / BLOCK_S)):
        samples = ramp.take(BLOCK_S)
        p.put(samples)
        put.append(samples)
        await clock.sleep(BLOCK_S)


def bound(window_s: float) -> float:
    """The most audio (s) the pacer may send within `window_s`: the pace plus its lead, plus one 100 ms piece."""
    return _CATCH_UP_SPEED * (window_s + _PACE_AHEAD_S) + 0.1 + 1e-6


def most_sent_within(sends: list[tuple[float, int]], window_s: float) -> float:
    """The most audio (s) sent in any `window_s` of time."""
    times = [t for t, _ in sends]
    sums = list(itertools.accumulate((n for _, n in sends), initial=0))
    best = 0
    for i, t in enumerate(times):
        j = bisect.bisect_right(times, t + window_s)
        best = max(best, sums[j] - sums[i])
    return best / RATE


@pytest.mark.parametrize("backlog_s", [6, 10, 15])
def test_a_startup_backlog_reaches_live_in_order_paced_and_catches_up(backlog_s):
    async def main():
        clock = FakeClock()
        p, ramp, put = pacer(clock), Ramp(), []
        for _ in range(round(backlog_s / BLOCK_S)):
            put.append(ramp.take(BLOCK_S))
            p.put(put[-1])
        send = Recorder(clock)
        p.start(send)
        catch_up_s = backlog_s / (_CATCH_UP_SPEED - 1)
        # The user keeps talking all along.
        mic = asyncio.ensure_future(speak(p, clock, ramp, catch_up_s + 10, put))
        await clock.run_until(catch_up_s + 10)
        await clock.run_until(clock.now() + 1)
        await mic
        await clock.run_until(catch_up_s + 11)
        lag = p.pending_samples / RATE
        await p.close()
        return send, put, lag, catch_up_s

    wall = time.monotonic()
    send, put, lag, catch_up_s = asyncio.run(main())
    assert time.monotonic() - wall < 10, "a fake clock must not wait for real"

    # Every sample, in the order heard; nothing trimmed.
    assert np.array_equal(np.concatenate(send.audio), np.concatenate(put))
    # Startup begins at once, and never runs past 1.2x real time beyond the small allowance: no burst.
    assert send.sends[0][0] == 0
    assert most_sent_within(send.sends, 1.0) <= bound(1.0)
    assert most_sent_within(send.sends, 5.0) <= bound(5.0)
    assert most_sent_within(send.sends, 0.0) <= bound(0.0)
    # Caught up when the 1.2x pace allows (backlog / 0.2 s), not before, then live again.
    assert lag <= 0.05
    sent = 0
    for t, n in send.sends:
        sent += n
        if sent >= RATE * (backlog_s + t - 2 * BLOCK_S):
            caught = t
            break
    # The 0.25 s allowance runs 1.2 x 0.25 s ahead, so it lands up to 1.5 s (plus 2 blocks) early.
    assert catch_up_s - 2.0 <= caught <= catch_up_s + 1


def test_once_caught_up_mic_audio_goes_at_once():
    async def main():
        clock = FakeClock()
        p, ramp, put = pacer(clock), Ramp(), []
        send = Recorder(clock)
        p.start(send)
        mic = asyncio.ensure_future(speak(p, clock, ramp, 5, put))
        await clock.run_until(6)
        await clock.run_until(clock.now() + 1)
        await mic
        await p.close()
        return send

    send = asyncio.run(main())
    # Each block leaves the moment it is heard: pacing adds no latency to live speech.
    assert [round(t, 6) for t, _ in send.sends] == [round(i * BLOCK_S, 6) for i in range(len(send.sends))]


def test_a_stalled_send_is_caught_up_paced_not_in_a_burst():
    async def main():
        clock = FakeClock()
        p, ramp, put = pacer(clock), Ramp(), []
        # Live takes 4 s to accept the 50th append.
        send = Recorder(clock, stall={50: 4.0})
        p.start(send)
        mic = asyncio.ensure_future(speak(p, clock, ramp, 40, put))
        await clock.run_until(41)
        await clock.run_until(clock.now() + 1)
        await mic
        await clock.run_until(42)
        await p.close()
        return send, put

    send, put = asyncio.run(main())
    assert np.array_equal(np.concatenate(send.audio), np.concatenate(put))
    # The idle time earned no credit: the 4 s held went at the pace, not at once.
    assert most_sent_within(send.sends, 1.0) <= bound(1.0)


def test_more_than_fifteen_seconds_held_before_start_is_an_error_not_a_trim():
    clock = FakeClock()
    p, ramp = pacer(clock), Ramp()
    accepted = 0
    with pytest.raises(MicOverflow, match="more than 15 s"):
        for _ in range(1000):
            p.put(ramp.take(BLOCK_S))
            accepted += 1
    assert accepted == round(15 / BLOCK_S)
    assert p.pending_samples == accepted * round(RATE * BLOCK_S)
    # It stays failed: no later block slips in after the gap.
    with pytest.raises(MicOverflow):
        p.put(ramp.take(BLOCK_S))


def test_a_live_that_stops_taking_audio_overflows_explicitly_and_cancels_cleanly():
    async def main():
        clock = FakeClock()
        p, ramp, put = pacer(clock), Ramp(), []
        stuck = asyncio.get_running_loop().create_future()
        sent: list[int] = []

        async def send(samples):
            sent.append(len(samples))
            await stuck

        p.start(send)
        mic = asyncio.ensure_future(speak(p, clock, ramp, 30, put))
        mic.add_done_callback(lambda _: overflow.append(clock.now()))
        overflow: list[float] = []
        await clock.run_until(30)
        with pytest.raises(MicOverflow):
            await mic
        (overflowed_at,) = overflow
        # Nothing heard was dropped: all but the overflowing block is still held, in flight included.
        assert p.pending_samples == sum(len(s) for s in put)
        task = p._task
        await p.close()
        return overflowed_at, sent, task, stuck, p

    overflowed_at, sent, task, stuck, p = asyncio.run(main())
    assert 14.9 <= overflowed_at <= 15.1
    assert sent == [round(RATE * BLOCK_S)]
    # Cancelled with its send in flight; nothing left queued or running.
    assert task.done() and task.cancelled()
    assert stuck.cancelled()
    assert p.pending_samples == 0


def test_a_failed_send_reaches_the_next_mic_block():
    async def main():
        clock = FakeClock()
        p, ramp = pacer(clock), Ramp()
        calls = 0

        async def send(samples):
            nonlocal calls
            calls += 1
            if calls == 3:
                raise ConnectionError("live socket closed")

        p.start(send)
        for _ in range(3):
            p.put(ramp.take(BLOCK_S))
            await clock.run_until(clock.now() + BLOCK_S)
        with pytest.raises(ConnectionError, match="live socket closed"):
            p.put(ramp.take(BLOCK_S))
        await asyncio.wait_for(p.drained(), 1)  # nothing waits forever on a dead pacer
        assert not await p.reached(p.put_samples)
        await p.close()

    asyncio.run(main())


def test_closing_mid_catch_up_stops_sending_and_drops_later_blocks():
    async def main():
        clock = FakeClock()
        p, ramp = pacer(clock), Ramp()
        for _ in range(round(15 / BLOCK_S)):
            p.put(ramp.take(BLOCK_S))
        send = Recorder(clock)
        p.start(send)
        await clock.run_until(2)
        await p.close()
        sent = len(send.sends)
        p.put(ramp.take(BLOCK_S))  # the device's last frames after the end: nowhere to go, no error
        await clock.run_until(10)
        return sent, len(send.sends), p

    sent, after, p = asyncio.run(main())
    assert sent == after
    assert p._task.done() and p.pending_samples == 0


def test_a_session_sends_mic_audio_only_through_the_pacer_backlog_first():
    async def main():
        clock = FakeClock()
        conn = Connection()
        session = await session_with(conn)
        session._mic = pacer(clock)
        for _ in range(80):
            await session.on_mic(block(1000, ms=100))  # 8 s before Live listens
        async with session.open(Host()):
            for _ in range(20):
                await session.on_mic(block(-1000, ms=100))  # heard while the backlog is still going out
            assert session._mic.pending_samples > RATE * 8
            await clock.run_until(60)
            await session._mic.drained()
        return conn

    conn = asyncio.run(main())
    audio = np.concatenate(conn.audio)
    assert len(audio) > RATE * 9.9
    first_late = int(np.argmax(audio < -500))
    # Everything heard after the session opened follows the whole backlog: nothing bypassed the pacer.
    assert first_late > RATE * 7.9
    assert not np.any(audio[first_late + 200 :] > 500)
    # And every append was a paced piece.
    assert max(len(a) for a in conn.audio) <= RATE // 10


def test_a_session_whose_start_fails_leaves_no_pacer_running():
    async def main():
        conn = Connection()

        async def refuse(session):
            raise RuntimeError("refused")

        conn.session.start = refuse

        @asynccontextmanager
        async def connect():
            yield conn

        session = await session_with(conn)
        session._connect = connect
        await session.on_mic(block(1000, ms=100))
        with pytest.raises(RuntimeError):
            async with session.open(Host()):
                pass
        return session

    session = asyncio.run(main())
    assert session._mic._task is None and session._mic.pending_samples == 0


def test_one_instant_sends_at_most_the_lead_and_one_piece():
    async def main():
        clock = FakeClock()
        p, ramp = pacer(clock), Ramp()
        for _ in range(10):
            p.put(ramp.take(1.0))  # one-second blocks: paced in 100 ms pieces
        send = Recorder(clock)
        p.start(send)
        await clock.run_until(20)
        await p.close()
        return send

    send = asyncio.run(main())
    assert max(n for _, n in send.sends) == RATE // 10
    # 1.2 x 0.25 s plus one 100 ms piece: 0.4 s, the exact bound.
    assert 0.35 < most_sent_within(send.sends, 0.0) <= bound(0.0)
    assert most_sent_within(send.sends, 1.0) <= bound(1.0)


def parallel_session(clock: FakeClock, conn: Conn, ears: Ears) -> LiveSession:
    @asynccontextmanager
    async def connect():
        yield conn

    session = LiveSession(
        Live(model="gpt-live-1", voice="marin", instructions=""),
        "Kitchen",
        lambda task: asyncio.sleep(0, "unused"),
        nothing_recent,
        connect,
        None,
        Parallel(ears),
    )
    session._mic = pacer(clock)
    return session


def test_home_assistant_is_told_only_after_live_has_heard_the_request(monkeypatch):
    monkeypatch.setattr(live, "_CLAIM_GRACE_S", 0.0)

    async def main():
        clock, conn, ears = FakeClock(), Conn(), Ears()
        session = parallel_session(clock, conn, ears)
        for _ in range(80):
            await session.on_mic(block(1000, ms=100))  # 8 s heard while Live starts; Home Assistant hears it live
        async with session.open(Host()):
            receiving = asyncio.create_task(session.receive())
            ears.did(1, Outcome.ACTED, "The kitchen light is off.")
            await asyncio.sleep(0.05)
            before = told(conn)
            await clock.run_until(5)  # 1.2 x (5 + 0.25) s sent: less than the 8 s request
            await asyncio.sleep(0.05)
            midway = told(conn)
            await clock.run_until(8)
            await asyncio.sleep(0.05)
            after = told(conn)
            await conn.events.put(None)
            await receiving
        return before, midway, after

    before, midway, after = asyncio.run(main())
    assert before == [] and midway == []
    assert after == [(None, "Home Assistant: The kitchen light is off.")]


def test_speech_over_the_assistant_is_dated_on_the_mic_including_the_pacer_lag():
    async def main():
        clock, conn, ears = FakeClock(), Conn(), Ears()
        session = parallel_session(clock, conn, ears)
        for _ in range(80):
            await session.on_mic(block(1000, ms=100))
        async with session.open(Host()):
            receiving = asyncio.create_task(session.receive())
            conn.assistant("Sure, ", 0, 2000)
            conn.user("wait", start_ms=1500)
            await asyncio.sleep(0.05)
            lag = session._mic.pending_samples / SPEAKER_RATE
            await conn.events.put(None)
            await receiving
        return ears.heard, lag

    heard, lag = asyncio.run(main())
    # 2.5 s back on Live's timeline (its minimum), which trails the mic by what is still queued.
    assert lag > 7
    assert heard == [pytest.approx(2.5 + lag, abs=0.01)]


def run_overflowing(make_config, stall_after_start: bool):
    async def main():
        config = make_config()
        device = SimDevice(talk_after_s=0.3)
        scripted = ScriptedLive(device)
        if stall_after_start:

            async def stuck(audio: str) -> None:
                await asyncio.Event().wait()

            scripted.session.input_audio.append = stuck

        @asynccontextmanager
        async def connect():
            yield scripted

        async def slow_recall():
            if not stall_after_start:
                await asyncio.sleep(30)  # the session never gets to start before the hold overflows
            return []

        session = LiveSession(config.live, "Kitchen", lambda task: asyncio.sleep(0, ""), slow_recall, connect)
        session._mic = _MicPacer(SPEAKER_RATE, SPEAKER_RATE // 2)  # 0.5 s, so it overflows quickly
        conversation = Conversation(config, "test", device, session, EchoCanceller(MIC_RATE))
        reason = await asyncio.wait_for(conversation.run(), 10)
        return reason, device, scripted

    return asyncio.run(main())


def test_an_overflow_while_live_starts_ends_the_conversation_without_starting_a_session(make_config):
    reason, device, scripted = run_overflowing(make_config, stall_after_start=False)
    assert reason == EndReason.MIC_OVERFLOW
    assert scripted.calls == []  # no billed session was started
    assert device.controls[-1][0] == ControlType.END


def test_an_overflow_mid_conversation_ends_it_with_that_reason(make_config):
    reason, device, scripted = run_overflowing(make_config, stall_after_start=True)
    assert reason == EndReason.MIC_OVERFLOW
    assert [name for name, _ in scripted.calls][:1] == ["session.start"]
    assert device.controls[-1][0] == ControlType.END


def test_cancellations_during_cleanup_still_stop_home_assistant_and_the_tasks():
    class SlowClose(_MicPacer):
        def __init__(self) -> None:
            super().__init__(SPEAKER_RATE, _BACKLOG_MAX_SAMPLES)
            self.closes = 0

        async def close(self) -> None:
            self.closes += 1
            if self.closes <= 2:
                await asyncio.Event().wait()
            await super().close()

    async def main():
        conn, ears = Conn(), Ears()
        session = parallel_session(FakeClock(), conn, ears)
        session._mic = SlowClose()
        inside = asyncio.Event()

        async def use():
            async with session.open(Host()):
                inside.set()
                await asyncio.Event().wait()

        task = asyncio.create_task(use())
        await inside.wait()
        background = list(session._tasks)
        for _ in range(3):  # the replaced conversation is cancelled while it tears down
            task.cancel()
            for _ in range(5):
                await asyncio.sleep(0)
        await asyncio.gather(task, return_exceptions=True)
        await asyncio.sleep(0)
        return ears, background

    ears, background = asyncio.run(main())
    assert ears.stopped
    assert background and all(t.done() for t in background)
