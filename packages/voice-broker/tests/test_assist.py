"""Home Assistant's Assist pipeline on the conversation's audio, against a scripted Home Assistant WebSocket."""

from __future__ import annotations

import asyncio
import json
from collections.abc import Awaitable, Callable

import numpy as np
import pytest
from voice_broker import assist
from voice_broker.assist import (
    HeardSpeech,
    HomeListener,
    HomeTurn,
    Outcome,
    ToolPolicy,
    ToolUse,
    Unavailable,
    _Run,
    _turn,
)
from voice_broker.protocol import MIC_RATE
from websockets.exceptions import ConnectionClosedError

PIPELINE = "Voice broker home"
PIPELINE_ID = "01JPIPE"
KITCHEN = "70f12d431cf502faeefdc782b45c0719"
ROOM = "9290a2568e3df21ba0fd2d663249c0ca"
POLICY = ToolPolicy(frozenset({"GetLiveContext", "GetDateTime"}), frozenset({"ask_gpt"}))
BLOCK = MIC_RATE // 100  # the conversation's 10 ms blocks
MS = MIC_RATE // 1000


class Run:
    """One run as the fake Home Assistant sees it."""

    def __init__(self, socket: Socket, msg_id: int, command: dict, handler: int) -> None:
        self.socket = socket
        self.msg_id = msg_id
        self.command = command
        self.handler = handler
        self.frames: list[bytes] = []
        self.cancelled = False
        self._got = asyncio.Event()

    @property
    def samples(self) -> np.ndarray:
        return np.frombuffer(b"".join(f[1:] for f in self.frames), dtype="<i2")

    async def heard(self, n: int) -> None:
        while len(self.samples) < n:
            self._got.clear()
            await self._got.wait()

    def receive(self, frame: bytes) -> None:
        self.frames.append(frame)
        self._got.set()

    def event(self, kind: str, **data) -> None:
        self.socket.out.put_nowait(
            json.dumps({"id": self.msg_id, "type": "event", "event": {"type": kind, "data": data}})
        )

    def speech(self, start_ms: int, end_ms: int) -> None:
        self.event("stt-vad-start", timestamp=start_ms)
        self.event("stt-vad-end", timestamp=end_ms)

    def intent(
        self,
        speech: str,
        *,
        tools=(),
        local=False,
        response_type="action_done",
        targets=False,
        conversation_id="01JCONV",
        question=False,
        text="turn on the kitchen light",
    ) -> None:
        self.event("stt-end", stt_output={"text": text})
        self.event("intent-start", engine="conversation.voice_home")
        for name, args in tools:
            self.event(
                "intent-progress",
                chat_log_delta={"tool_calls": [{"tool_name": name, "tool_args": args, "id": "t", "external": False}]},
            )
            self.event(
                "intent-progress",
                chat_log_delta={
                    "role": "tool_result",
                    "tool_name": name,
                    "tool_call_id": "t",
                    "result": {"data": {}, "error": False},
                },
            )
        data = (
            {"success": [{"name": "Kitchen", "type": "area", "id": "kitchen"}], "failed": []}
            if targets
            else {"success": [], "failed": []}
        )
        self.event(
            "intent-end",
            processed_locally=local,
            intent_output={
                "response": {"speech": {"plain": {"speech": speech}}, "response_type": response_type, "data": data},
                "conversation_id": conversation_id,
                "continue_conversation": question,
            },
        )
        self.event("run-end")


Script = Callable[[Run], Awaitable[None]]


class Socket:
    def __init__(self, ha: FakeHA) -> None:
        self.ha = ha
        self.out: asyncio.Queue[str | None] = asyncio.Queue()
        self.closed = False
        self.runs: dict[int, Run] = {}
        # Binary sends wait on this while cleared: a slow Home Assistant.
        self.flowing = asyncio.Event()
        self.flowing.set()

    async def send(self, message: str | bytes) -> None:
        assert not self.closed
        if isinstance(message, bytes):
            await self.flowing.wait()
            assert len(message) > 1, "the broker never ends the audio itself"
            run = self.runs.get(message[0])
            assert run is not None, "audio before run-start"
            run.receive(message)
            return
        command = json.loads(message)
        self.ha.commands.append(command)
        match command.get("type"):
            case "auth":
                self.out.put_nowait(json.dumps({"type": "auth_ok" if self.ha.auth else "auth_invalid"}))
            case "assist_pipeline/pipeline/list":
                self._result(command, {"pipelines": self.ha.pipelines, "preferred_pipeline": None})
            case "assist_pipeline/run":
                self._result(command, None)
                if not self.ha.scripts:
                    return  # Home Assistant never gets to this run
                handler = len(self.ha.runs) + 1
                run = Run(self, command["id"], command, handler)
                self.ha.runs.append(run)
                self.runs[handler] = run
                run.event(
                    "run-start",
                    pipeline=PIPELINE_ID,
                    language="en",
                    runner_data={"stt_binary_handler_id": handler, "timeout": 60},
                )
                run.event("stt-start", engine="stt.groq", metadata={})
                script = self.ha.scripts.pop(0)
                self.ha.tasks.append(asyncio.create_task(script(run)))
            case "unsubscribe_events":
                for run in self.runs.values():
                    if run.msg_id == command["subscription"]:
                        run.cancelled = True
                self._result(command, None)

    def _result(self, command: dict, result) -> None:
        self.out.put_nowait(json.dumps({"id": command["id"], "type": "result", "success": True, "result": result}))

    async def recv(self) -> str:
        message = await self.out.get()
        if message is None:
            raise ConnectionClosedError(None, None)
        return message

    def drop(self) -> None:
        """The connection is lost."""
        self.out.put_nowait(None)

    async def close(self) -> None:
        self.closed = True


class FakeHA:
    def __init__(self, *scripts: Script, pipelines: list[dict] | None = None, auth: bool = True) -> None:
        self.scripts = list(scripts)
        self.pipelines = [{"id": PIPELINE_ID, "name": PIPELINE}] if pipelines is None else pipelines
        self.auth = auth
        self.sockets: list[Socket] = []
        self.commands: list[dict] = []
        self.runs: list[Run] = []
        self.tasks: list[asyncio.Task] = []

    async def connect(self, url: str, **kwargs) -> Socket:
        assert url == "ws://ha.test:8123/api/websocket"
        socket = Socket(self)
        self.sockets.append(socket)
        socket.out.put_nowait(json.dumps({"type": "auth_required", "ha_version": "2026.10.1"}))
        return socket

    @property
    def run_commands(self) -> list[dict]:
        return [c for c in self.commands if c["type"] == "assist_pipeline/run"]


class Clock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def listener(
    ha: FakeHA, device: str = KITCHEN, lock: asyncio.Lock | None = None, clock: Clock | None = None
) -> HomeListener:
    return HomeListener(
        "http://ha.test:8123",
        "ha-token",
        PIPELINE,
        device,
        POLICY,
        lock or asyncio.Lock(),
        ha.connect,
        clock or Clock(),
    )


def counting(start: int, n: int) -> np.ndarray:
    """Audio whose every sample is its own index (mod 2^15), so where each arrived can be checked."""
    return (np.arange(start, start + n) % 32768).astype(np.int16)


def feed(home: HomeListener, seconds: float, audible: bool = False) -> None:
    for _ in range(int(seconds * 100)):
        home.feed(counting(home._next_index, BLOCK), audible)


async def settle(times: int = 20) -> None:
    for _ in range(times):
        await asyncio.sleep(0)


async def until(predicate, limit: float = 2.0) -> None:
    async with asyncio.timeout(limit):
        while not predicate():
            await asyncio.sleep(0.001)


async def next_event(home: HomeListener):
    async with asyncio.timeout(2):
        return await home.events.get()


def drained(home: HomeListener) -> list:
    events = []
    while not home.events.empty():
        events.append(home.events.get_nowait())
    return events


# -- wire format -------------------------------------------------------------


def test_each_utterance_is_one_stt_to_intent_run_of_16k_pcm_after_run_start():
    async def utterance(run: Run) -> None:
        await run.heard(MIC_RATE)
        run.speech(start_ms=300, end_ms=900)
        run.intent("Turned on the kitchen light.", tools=[("intent__HassTurnOn", {"area": "Kitchen"})])

    async def main():
        ha = FakeHA(utterance)
        home = listener(ha)
        # Audio before Home Assistant is even connected is kept, and sent once the run starts.
        feed(home, 1.0)
        home.start()
        assert isinstance(await next_event(home), HeardSpeech)
        turn = await next_event(home)
        home.stop()
        return ha, turn

    ha, turn = asyncio.run(main())
    (command,) = ha.run_commands[:1]
    assert command["start_stage"] == "stt" and command["end_stage"] == "intent"
    assert command["input"] == {"sample_rate": 16000}
    # Resolved by name; the speaker's own ESPHome device, which places unplaced requests.
    assert command["pipeline"] == PIPELINE_ID and command["device_id"] == KITCHEN
    assert "conversation_id" not in command
    run = ha.runs[0]
    # Every binary frame is the handler id, then little-endian PCM16, and the conversation's audio from its start.
    assert all(f[0] == run.handler for f in run.frames)
    assert np.array_equal(run.samples[:MIC_RATE], counting(0, MIC_RATE))
    assert turn == HomeTurn(
        1,
        Outcome.ACTED,
        "Turned on the kitchen light.",
        "turn on the kitchen light",
        (ToolUse("intent__HassTurnOn", {"area": "Kitchen"}, False),),
        300 * MS,
        900 * MS,
    )


def test_audio_past_the_end_of_speech_starts_the_next_run_with_nothing_lost_or_repeated():
    async def first(run: Run) -> None:
        await run.heard(MIC_RATE + 7 * BLOCK)
        run.speech(start_ms=200, end_ms=1000)
        await asyncio.sleep(0.01)
        run.intent("Done.", tools=[("intent__HassTurnOff", {})])

    async def second(run: Run) -> None:
        await run.heard(MIC_RATE // 2)
        run.speech(start_ms=100, end_ms=400)
        run.intent("Which light, the kitchen or the hallway?", question=True, conversation_id="01JQ")

    async def main():
        ha = FakeHA(first, second)
        home = listener(ha)
        home.start()
        feed(home, 3.0)
        events = [await next_event(home) for _ in range(4)]
        home.stop()
        return ha, events

    ha, events = asyncio.run(main())
    _, second_run = ha.runs
    end = 1000 * MS
    # The next run starts exactly where the first one's speech ended.
    assert np.array_equal(second_run.samples[:BLOCK], counting(end, BLOCK))
    turns = [e for e in events if isinstance(e, HomeTurn)]
    assert [t.outcome for t in turns] == [Outcome.ACTED, Outcome.ASKED]
    # The second run's speech is located in the conversation's audio, not its own.
    assert turns[1].speech_start == end + 100 * MS


def test_runs_never_overlap_and_the_conversation_continues_in_home_assistant():
    """Which light? -> Kitchen: the answer is a new run, in the same Home Assistant conversation."""
    started_second_during_first: list[bool] = []

    async def asks(run: Run) -> None:
        await run.heard(MIC_RATE)
        run.speech(start_ms=200, end_ms=800)
        run.event("stt-end", stt_output={"text": "turn on the light"})
        run.event("intent-start")
        await asyncio.sleep(0.05)
        started_second_during_first.append(len(run.socket.ha.run_commands) > 1)
        run.intent("Which light, the kitchen or the hallway?", question=True, conversation_id="01JQ")

    async def answers(run: Run) -> None:
        await run.heard(MIC_RATE // 2)
        run.speech(start_ms=100, end_ms=400)
        run.intent(
            "The kitchen light is on.",
            tools=[("intent__HassTurnOn", {"name": "Kitchen light"})],
            conversation_id="01JQ",
            text="kitchen",
        )

    async def main():
        ha = FakeHA(asks, answers)
        home = listener(ha)
        home.start()
        feed(home, 3.0)
        turns = []
        while len(turns) < 2:
            if isinstance(event := await next_event(home), HomeTurn):
                turns.append(event)
        home.stop()
        return ha, turns

    ha, turns = asyncio.run(main())
    assert started_second_during_first == [False]
    assert [t.outcome for t in turns] == [Outcome.ASKED, Outcome.ACTED]
    assert ha.run_commands[1]["conversation_id"] == "01JQ"


# -- end of speech belongs to Home Assistant ---------------------------------


def test_a_run_hearing_no_speech_restarts_before_home_assistants_timeout_keeping_its_newest_second():
    async def silent(run: Run) -> None:
        await asyncio.Event().wait()  # Home Assistant hears nothing

    async def speaks(run: Run) -> None:
        await run.heard(MIC_RATE)
        run.speech(start_ms=300, end_ms=700)
        run.intent("", text="")

    async def main():
        ha = FakeHA(silent, speaks)
        home = listener(ha)
        home.start()
        feed(home, 8.0)
        await until(lambda: len(ha.runs) == 2 and len(ha.runs[1].samples) >= MIC_RATE)
        await settle()
        home.stop()
        return ha, home

    ha, home = asyncio.run(main())
    first, second = ha.runs
    assert first.cancelled
    sent = len(first.samples)
    assert sent == assist.IDLE_RESTART_S * MIC_RATE
    keep = int(assist.RESTART_KEEP_S * MIC_RATE)
    # The newest second goes again, to the run that may hear it as speech.
    assert np.array_equal(second.samples[:keep], counting(sent - keep, keep))
    # An idle restart is no turn.
    assert all(e.turn != 1 for e in drained(home))
    assert not any(c["type"] == "unsubscribe_events" and c["subscription"] == second.msg_id for c in ha.commands)


def test_a_vad_timeout_without_speech_is_cancelled_before_whisper_can_act_on_silence():
    async def timed_out(run: Run) -> None:
        await run.heard(MIC_RATE // 2)
        run.event("stt-vad-end", timestamp=15000)
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(timed_out)
        home = listener(ha)
        home.start()
        feed(home, 1.0)
        await until(lambda: ha.runs and ha.runs[0].cancelled)
        await settle()
        home.stop()
        return home

    home = asyncio.run(main())
    assert drained(home) == []


# -- failures ------------------------------------------------------------------


def test_no_text_after_speech_is_a_failure_that_did_nothing_and_without_speech_is_nothing():
    async def no_text(run: Run) -> None:
        await run.heard(MIC_RATE)
        run.speech(start_ms=300, end_ms=800)
        run.event("error", code="stt-no-text-recognized", message="No text recognized")
        run.event("run-end")

    async def main():
        ha = FakeHA(no_text)
        home = listener(ha)
        home.start()
        feed(home, 2.0)
        events = [await next_event(home), await next_event(home)]
        home.stop()
        return events

    _, turn = asyncio.run(main())
    assert turn.outcome == Outcome.FAILED and turn.reason == "stt-no-text-recognized"


def test_an_error_after_the_intent_stage_began_is_uncertain_and_never_retried():
    async def fails_late(run: Run) -> None:
        await run.heard(MIC_RATE)
        run.speech(start_ms=300, end_ms=800)
        run.event("stt-end", stt_output={"text": "turn off the heating"})
        run.event("intent-start")
        run.event(
            "intent-progress",
            chat_log_delta={"tool_calls": [{"tool_name": "climate__HassClimateSetTemperature", "tool_args": {}}]},
        )
        run.event("error", code="intent-failed", message="Unexpected error")
        run.event("run-end")

    async def idle(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(fails_late, idle)
        home = listener(ha)
        home.start()
        feed(home, 2.0)
        events = [await next_event(home), await next_event(home)]
        await until(lambda: len(ha.runs) == 2 and len(ha.runs[1].samples) > 0)
        home.stop()
        return ha, events

    ha, (_, turn) = asyncio.run(main())
    assert turn.outcome == Outcome.UNCERTAIN and turn.reason == "intent-failed"
    # The next run carries only audio after the failed utterance: its speech is never sent again.
    assert ha.runs[1].samples[0] == counting(800 * MS, 1)[0]


def test_a_connection_lost_during_the_intent_stage_is_uncertain_and_the_utterance_is_not_replayed():
    async def lost(run: Run) -> None:
        await run.heard(MIC_RATE)
        run.speech(start_ms=300, end_ms=800)
        run.event("intent-start")
        run.socket.drop()

    async def after(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(lost, after)
        home = listener(ha)
        home.start()
        feed(home, 2.0)
        events = [await next_event(home), await next_event(home)]
        await until(lambda: len(ha.runs) == 2 and len(ha.runs[1].samples) > 0)
        home.stop()
        return ha, events

    ha, (_, turn) = asyncio.run(main())
    assert turn.outcome == Outcome.UNCERTAIN and turn.reason == "connection lost"
    assert len(ha.sockets) == 2
    # A reconnect continues with later audio only.
    assert int(ha.runs[1].samples[0]) >= 800 * MS


def test_a_missing_pipeline_makes_home_assistant_unavailable_without_running_anything():
    async def main():
        ha = FakeHA(pipelines=[{"id": "01JOTHER", "name": "Remote"}])
        home = listener(ha)
        home.start()
        feed(home, 0.5)
        event = await next_event(home)
        return ha, event

    ha, event = asyncio.run(main())
    assert event == Unavailable(f"0 pipelines named {PIPELINE!r}")
    assert ha.run_commands == []


def test_refused_authentication_makes_home_assistant_unavailable():
    async def main():
        home = listener(FakeHA(auth=False))
        home.start()
        return await next_event(home)

    assert asyncio.run(main()) == Unavailable("authentication refused")


# -- conversation end -----------------------------------------------------------


def test_ending_the_conversation_before_the_intent_stage_cancels_the_run():
    async def listening(run: Run) -> None:
        await run.heard(MIC_RATE)
        run.event("stt-vad-start", timestamp=300)
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(listening)
        home = listener(ha)
        home.start()
        feed(home, 1.5)
        await next_event(home)
        finishing = home.stop()
        await settle()
        return ha, finishing

    ha, finishing = asyncio.run(main())
    assert finishing is None
    # Closing the socket is Home Assistant's cancellation of the run (websocket_api.py).
    assert ha.sockets[0].closed
    assert len(ha.run_commands) == 1


def test_ending_the_conversation_during_the_intent_stage_lets_it_finish_and_starts_nothing_new():
    async def acting(run: Run) -> None:
        await run.heard(MIC_RATE)
        run.speech(start_ms=300, end_ms=800)
        run.event("intent-start")
        await run.socket.ha.gate.wait()
        run.intent("Heating off.", tools=[("climate__HassTurnOff", {})])

    async def main():
        ha = FakeHA(acting, acting)
        ha.gate = asyncio.Event()
        home = listener(ha)
        home.start()
        feed(home, 2.0)
        await next_event(home)
        await until(lambda: home._run is not None and home._run.intent_started)
        finishing = home.stop()
        assert finishing is not None and not finishing.done()
        ha.gate.set()
        await asyncio.wait_for(finishing, 2)
        return ha, home

    ha, home = asyncio.run(main())
    assert len(ha.run_commands) == 1
    assert [e.outcome for e in drained(home) if isinstance(e, HomeTurn)] == [Outcome.ACTED]
    assert ha.sockets[0].closed


# -- backpressure -----------------------------------------------------------------


def test_feeding_never_waits_on_home_assistant_and_the_backlog_is_bounded():
    async def slow(run: Run) -> None:
        await run.heard(BLOCK)
        run.event("stt-vad-start", timestamp=10)
        run.socket.flowing.clear()  # Home Assistant stops reading
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(slow)
        home = listener(ha)
        home.start()
        feed(home, 0.2)
        await until(lambda: ha.runs and not ha.sockets[0].flowing.is_set())
        # Past the bound, fed synchronously: nothing here can await Home Assistant.
        feed(home, assist.MAX_BACKLOG_S + 20.0)
        queued = home._queued
        ha.sockets[0].flowing.set()
        event = None
        while not isinstance(event, HomeTurn):
            event = await next_event(home)
        home.stop()
        return queued, event, ha

    queued, turn, ha = asyncio.run(main())
    assert queued <= assist.MAX_BACKLOG_S * MIC_RATE
    # The utterance lost audio: it is cancelled before Home Assistant could act on a part of it.
    assert turn.outcome == Outcome.FAILED and turn.reason == "audio backlog"
    assert ha.runs[0].cancelled


# -- echo and barge-in ------------------------------------------------------------


def test_audio_while_the_assistant_is_audible_never_reaches_speech_recognition():
    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 0.5)
        feed(home, 2.0, audible=True)
        feed(home, 0.2)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 0.3)
        await until(lambda: ha.runs and len(ha.runs[0].samples) >= int(2.0 * MIC_RATE))
        home.stop()
        return ha.runs[0].samples

    samples = asyncio.run(main())
    before, audible_end = int(0.5 * MIC_RATE), int(2.5 * MIC_RATE)
    # The audio before it, silence for the echo (up to ECHO_SILENCE_S), then the audio after it:
    # nothing of the 2 s in between.
    expected = np.concatenate(
        [counting(0, before), np.zeros(MIC_RATE, np.int16), counting(audible_end, int(0.5 * MIC_RATE))]
    )
    assert np.array_equal(samples[: len(expected)], expected)


def test_speech_over_the_assistant_goes_on_whole_from_shortly_before_its_transcript_began(monkeypatch):
    monkeypatch.setattr(assist, "IDLE_RESTART_S", 100.0)

    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 3.0, audible=True)
        # GPT-Live heard the user start 1.5 s ago, over the assistant; it goes on a while, then yields.
        home.user_heard(1.5)
        feed(home, 3.0, audible=True)
        feed(home, 0.2)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 0.3)
        await until(lambda: ha.runs and len(ha.runs[0].samples) >= int(4.5 * MIC_RATE))
        home.stop()
        return ha.runs[0].samples

    samples = asyncio.run(main())
    keep_from = int((3.0 - 1.5 - assist.BARGE_IN_PREROLL_S) * MIC_RATE)
    expected = np.concatenate(
        [
            # The echo before the user's words: silence, as long as it was, up to ECHO_SILENCE_S.
            np.zeros(MIC_RATE, np.int16),
            # Their words, from just before they began, never cut to the last second.
            counting(keep_from, 3 * MIC_RATE - keep_from),
            # The assistant went on for long after their transcript, which more speech would have
            # extended: what follows is echo alone, silence, not the rest of the reply.
            np.zeros(MIC_RATE, np.int16),
            counting(6 * MIC_RATE, int(0.5 * MIC_RATE)),
        ]
    )
    assert np.array_equal(samples[: len(expected)], expected)


def test_a_backchannel_while_the_user_talks_reaches_home_assistant_whole():
    async def acts(run: Run) -> None:
        await run.heard(int(0.5 * MIC_RATE))
        run.event("stt-vad-start", timestamp=300)
        await run.heard(int(2.3 * MIC_RATE))
        run.event("stt-vad-end", timestamp=2300)
        run.intent("Turned on the kitchen light.", tools=[("intent__HassTurnOn", {"area": "Kitchen"})])

    async def main():
        clock = Clock()
        ha = FakeHA(acts)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 0.6)  # "turn on the kitchen..."
        await until(lambda: home._run is not None and home._run.vad_start_ms is not None)
        feed(home, 0.8, audible=True)  # GPT-Live: "mm-hm", while the user goes on: "...light"
        home.user_heard(1.5)
        clock.now += 1.0
        feed(home, 0.2)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 1.0)
        event = None
        while not isinstance(event, HomeTurn):
            event = await next_event(home)
        home.stop()
        return event, ha

    turn, ha = asyncio.run(main())
    assert turn.outcome == Outcome.ACTED and not ha.runs[0].cancelled
    # Not spliced: Home Assistant heard the utterance as it was spoken.
    assert np.array_equal(ha.runs[0].samples[: int(2.4 * MIC_RATE)], counting(0, int(2.4 * MIC_RATE)))


def test_a_backchannel_in_the_users_pause_is_silence_so_the_utterance_ends_as_it_was():
    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 0.6)
        feed(home, 0.4, audible=True)  # "mm-hm" while the user pauses; nobody speaks over it
        feed(home, 0.2)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 0.3)
        await until(lambda: ha.runs and len(ha.runs[0].samples) >= int(1.5 * MIC_RATE))
        home.stop()
        return ha.runs[0].samples

    samples = asyncio.run(main())
    # The pause stays a pause of the same length: no echo, nothing removed, so the timing is the user's.
    expected = np.concatenate(
        [
            counting(0, int(0.6 * MIC_RATE)),
            np.zeros(int(0.4 * MIC_RATE), np.int16),
            counting(MIC_RATE, int(0.5 * MIC_RATE)),
        ]
    )
    assert np.array_equal(samples[: len(expected)], expected)


def test_a_hold_whose_start_was_dropped_is_never_acted_on_in_part(monkeypatch):
    monkeypatch.setattr(assist, "HOLD_MAX_S", 2.0)

    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        feed(home, 3.0, audible=True)
        home.user_heard(4.0)  # the user began before the oldest audio still held
        clock.now += 3.0
        feed(home, 0.1)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 0.1)
        return home

    home = asyncio.run(main())
    # Marked from the oldest audio still held, so speech it cuts is cancelled, and told.
    assert home._overrun and home._gap_reason == "speech cut" and home._gap_at >= MIC_RATE


# -- devices --------------------------------------------------------------------


def test_each_speaker_runs_as_its_own_device_and_one_speakers_runs_wait_for_each_other():
    async def hangs(run: Run) -> None:
        await run.heard(BLOCK)
        run.event("stt-vad-start", timestamp=10)
        run.event("intent-start")
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(hangs, hangs, hangs)
        kitchen_lock = asyncio.Lock()
        kitchen = listener(ha, KITCHEN, kitchen_lock)
        room = listener(ha, ROOM)
        # A second conversation at the kitchen speaker while the first's run is under way.
        kitchen_again = listener(ha, KITCHEN, kitchen_lock)
        for home in (kitchen, room, kitchen_again):
            home.start()
            feed(home, 0.1)
        await until(lambda: len(ha.run_commands) >= 2)
        await asyncio.sleep(0.02)
        devices = [c["device_id"] for c in ha.run_commands]
        for home in (kitchen, room, kitchen_again):
            home.stop()
        for task in ha.tasks:
            task.cancel()
        return devices

    devices = asyncio.run(main())
    assert sorted(devices) == sorted([KITCHEN, ROOM])


# -- evidence of ownership --------------------------------------------------------


def outcome(
    *, tools=(), local=False, response_type="action_done", targets=False, question=False, speech="Okay.", intent=True
):
    run = _Run(1)
    run.intent_started = intent
    run.tools = [ToolUse(n, {}, external=e) for n, e in tools]
    run.processed_locally = local
    data = {"success": [{"id": "light.kitchen"}], "failed": []} if targets else {"success": [], "failed": []}
    run.output = {
        "response": {"speech": {"plain": {"speech": speech}}, "response_type": response_type, "data": data},
        "conversation_id": "01J",
        "continue_conversation": question,
    }
    return _turn(run, POLICY, "").outcome


@pytest.mark.parametrize(
    ("kwargs", "expected"),
    [
        # The LLM agent answering anything with a blank action_done: no evidence it did anything.
        ({}, Outcome.ABSTAINED),
        ({"speech": "Tomorrow will be sunny."}, Outcome.ABSTAINED),
        ({"tools": [("intent__HassTurnOn", False)]}, Outcome.ACTED),
        ({"tools": [("homeassistant__GetLiveContext", False)]}, Outcome.ANSWERED),
        ({"tools": [("homeassistant__GetLiveContext", False), ("light__HassLightSet", False)]}, Outcome.ACTED),
        # Work beyond the home is no home ownership, whether an exposed script or the provider's own tool.
        ({"tools": [("script__ask_gpt", False)]}, Outcome.ABSTAINED),
        ({"tools": [("web_search", True)]}, Outcome.ABSTAINED),
        ({"local": True, "targets": True}, Outcome.ACTED),
        ({"local": True, "targets": True, "response_type": "query_answer"}, Outcome.ANSWERED),
        # A local answer about nothing in the home, such as the time.
        ({"local": True, "response_type": "query_answer"}, Outcome.ABSTAINED),
        ({"question": True, "speech": "Which light?"}, Outcome.ASKED),
        # A follow-up question after an action hides nothing: it acted, and asks too.
        ({"tools": [("intent__HassTurnOn", False)], "question": True, "speech": "Done. Anything else?"}, Outcome.ACTED),
        # A local action without targets, such as a sentence trigger's automation.
        ({"local": True}, Outcome.ACTED),
        # "Never mind" (HassNevermind): local, no targets, no speech, nothing done.
        ({"local": True, "speech": ""}, Outcome.ABSTAINED),
        ({"local": True, "response_type": "error", "speech": "Sorry"}, Outcome.ABSTAINED),
        ({"response_type": "error", "speech": "Error talking to OpenAI"}, Outcome.FAILED),
    ],
)
def test_ownership_comes_from_tool_evidence_not_from_success(kwargs, expected):
    assert outcome(**kwargs) == expected


def test_a_run_without_its_intent_result_failed_before_the_intent_stage_and_is_uncertain_after():
    run = _Run(1)
    assert _turn(run, POLICY, "connection lost").outcome == Outcome.FAILED
    run.intent_started = True
    assert _turn(run, POLICY, "connection lost").outcome == Outcome.UNCERTAIN


# -- review findings of 2026-10-17 ------------------------------------------------


def test_the_rest_of_an_utterance_that_lost_audio_is_never_acted_on(monkeypatch):
    # The idle restart is out of the way: this is about the backlog's gap alone.
    monkeypatch.setattr(assist, "IDLE_RESTART_S", 100.0)

    async def slow(run: Run) -> None:
        await run.heard(BLOCK)
        run.event("stt-vad-start", timestamp=10)
        run.socket.flowing.clear()  # Home Assistant falls behind mid-utterance
        await asyncio.Event().wait()

    async def would_act_on_the_tail(run: Run) -> None:
        # The queue's head is the middle of the same utterance: speech at once.
        await run.heard(BLOCK)
        run.event("stt-vad-start", timestamp=300)
        await asyncio.sleep(0.05)
        if not run.cancelled:
            run.event("stt-vad-end", timestamp=900)
            run.intent("Done", tools=[("HassTurnOn", {"name": "light"})])

    async def main():
        ha = FakeHA(slow, would_act_on_the_tail, would_act_on_the_tail)
        home = listener(ha)
        home.start()
        feed(home, 0.2)
        await until(lambda: ha.runs and not ha.sockets[0].flowing.is_set())
        # The utterance began before anything was dropped.
        await until(lambda: home._run is not None and home._run.vad_start_ms is not None)
        feed(home, assist.MAX_BACKLOG_S + 20.0)  # far past the backlog's bound: its oldest audio is dropped
        ha.sockets[0].flowing.set()
        # A fourth run is asked for once the rest has been cancelled twice.
        await until(lambda: len(ha.run_commands) == 4)
        await settle()
        home.stop()
        return ha, drained(home)

    ha, events = asyncio.run(main())
    # The cut utterance is a failure that did nothing, and so is each cut piece of its rest: it could
    # also be a new request spoken at once, which is never dropped silently (live.py tells it once).
    turns = [e for e in events if isinstance(e, HomeTurn)]
    assert [(t.turn, t.outcome, t.reason) for t in turns] == [
        (1, Outcome.FAILED, "audio backlog"),
        (2, Outcome.FAILED, "speech cut"),
        (3, Outcome.FAILED, "speech cut"),
    ]
    # Its rest is cancelled before any intent stage.
    assert all(run.cancelled for run in ha.runs)
    assert [e.turn for e in events if isinstance(e, HeardSpeech)] == [1, 2, 3]
    # Each cancellation moved on past the speech it saw, and kept the audio after it for the next run.
    starts = [int(run.samples[0]) for run in ha.runs[1:]]
    assert starts[1] == (starts[0] + 300 * MS) % 32768


def test_speech_well_after_a_gap_is_heard_as_usual(monkeypatch):
    monkeypatch.setattr(assist, "IDLE_RESTART_S", 100.0)

    async def acts(run: Run) -> None:
        await run.heard(int(1.5 * MIC_RATE))
        # 1.2 s of the run's audio before speech: more than GAP_GUARD_S after the gap at its start.
        run.event("stt-vad-start", timestamp=1200)
        run.event("stt-vad-end", timestamp=1500)
        run.intent("Done", tools=[("HassTurnOn", {"name": "light"})])

    async def main():
        ha = FakeHA(acts)
        home = listener(ha)
        # A gap before the run's first audio, as left by an earlier overrun.
        home._gap_at = 0
        home._overrun = True
        home.start()
        feed(home, 2.0)
        event = None
        while not isinstance(event, HomeTurn):
            event = await next_event(home)
        home.stop()
        return event

    assert asyncio.run(main()).outcome == Outcome.ACTED


def test_a_backlog_sent_in_a_burst_waits_for_home_assistants_verdict_before_an_idle_restart(monkeypatch):
    monkeypatch.setattr(assist, "IDLE_SETTLE_S", 0.2)

    async def speech_late_in_the_backlog(run: Run) -> None:
        # Home Assistant reports the speech 4 s into the burst a moment after reading it: the
        # sender, at socket speed, is past 6 s by then.
        await run.heard(int(4.5 * MIC_RATE))
        run.event("stt-vad-start", timestamp=4000)
        run.event("stt-vad-end", timestamp=4600)
        run.intent("Done", tools=[("HassTurnOn", {"name": "light"})])

    async def main():
        ha = FakeHA(speech_late_in_the_backlog)
        home = listener(ha)
        feed(home, 8.0)  # queued before the run starts, as after a long intent stage
        home.start()
        event = None
        while not isinstance(event, HomeTurn):
            event = await next_event(home)
        home.stop()
        return ha, event

    ha, turn = asyncio.run(main())
    assert turn.outcome == Outcome.ACTED
    assert not ha.runs[0].cancelled


def test_a_trailing_transcript_as_the_assistant_starts_is_no_barge_in():
    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 2.0, audible=True)  # GPT-Live replying
        # The end of the user's previous utterance, transcribed late: GPT-Live's timeline puts it
        # before the assistant's speech (live.py), so it is not over the assistant.
        home.user_heard(None)
        clock.now += 4.0
        feed(home, 2.0, audible=True)  # the reply goes on; nobody spoke over it
        feed(home, 0.1)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 0.4)
        await until(lambda: ha.runs and len(ha.runs[0].samples) >= int(1.4 * MIC_RATE))
        home.stop()
        return ha.runs[0].samples

    samples = asyncio.run(main())
    # Nothing of the assistant's 4 s reaches speech recognition: silence, then what follows it.
    assert not samples[:MIC_RATE].any() and int(samples[MIC_RATE]) == (4 * MIC_RATE) % 32768


def test_a_pause_the_assistant_speaks_again_in_is_not_lost():
    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 1.0, audible=True)
        feed(home, 0.2)  # a pause, still undecided: barge-in or not
        feed(home, 1.0, audible=True)  # the assistant again
        clock.now += 5.0
        feed(home, 0.3)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 0.3)
        await until(lambda: ha.runs and len(ha.runs[0].samples) >= int(1.2 * MIC_RATE))
        home.stop()
        return ha.runs[0].samples

    samples = asyncio.run(main())
    # The pause was heard while the assistant was silent, so it goes on, after the first reply's silence.
    assert np.array_equal(samples[MIC_RATE : int(1.2 * MIC_RATE)], counting(MIC_RATE, int(0.2 * MIC_RATE)))


def test_speech_over_the_assistant_in_a_pause_it_speaks_again_in_still_counts():
    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 1.0, audible=True)
        feed(home, 0.5)  # "wait—", in the pause
        feed(home, 1.0, audible=True)  # the assistant speaks again before the pause is decided
        home.user_heard(1.5)  # the transcript of "wait—" arrives
        clock.now += 1.0
        feed(home, 0.2)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 0.3)
        await until(lambda: ha.runs and len(ha.runs[0].samples) >= int(2.0 * MIC_RATE))
        home.stop()
        return ha.runs[0].samples

    samples = asyncio.run(main())
    # From 0.5 s into the first reply on: none of it lost to the assistant speaking again.
    assert not samples[: MIC_RATE // 2].any()
    assert np.array_equal(samples[MIC_RATE // 2 : 2 * MIC_RATE], counting(MIC_RATE // 2, int(1.5 * MIC_RATE)))


def test_an_idle_run_starts_afresh_before_home_assistants_wall_clock_timeout(monkeypatch):
    monkeypatch.setattr(assist, "IDLE_RUN_AGE_S", 0.1)

    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens, listens)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 0.1)
        await until(lambda: ha.runs)
        # The assistant speaks on and on: nothing is sent, so no idle restart by audio could come.
        feed(home, 3.0, audible=True)
        clock.now += 1.0
        await until(lambda: len(ha.runs) == 2)
        home.stop()
        return ha

    ha = asyncio.run(main())
    assert ha.runs[0].cancelled


def test_a_listener_bug_reports_the_run_it_cut_off_and_home_assistant_unavailable(monkeypatch):
    def broken(run, delta):
        raise RuntimeError("bug")

    monkeypatch.setattr(assist, "_record", broken)

    async def acts(run: Run) -> None:
        await run.heard(BLOCK)
        run.speech(start_ms=300, end_ms=700)
        run.intent("Done", tools=[("HassTurnOn", {"name": "light"})])

    async def main():
        ha = FakeHA(acts)
        home = listener(ha)
        home.start()
        feed(home, 1.5)
        events = []
        while not any(isinstance(e, Unavailable) for e in events):
            events.append(await next_event(home))
        home.stop()
        return events

    events = asyncio.run(main())
    (turn,) = [e for e in events if isinstance(e, HomeTurn)]
    # It reached the intent stage, so it may have acted; and the conversation is told Home Assistant is gone.
    assert turn.outcome == Outcome.UNCERTAIN and turn.reason == "internal RuntimeError"
    assert any(isinstance(e, Unavailable) and e.reason == "internal error" for e in events)


def test_a_message_already_on_its_way_is_read_before_a_restart():
    class Late:
        async def recv(self) -> str:
            await asyncio.sleep(0.05)
            return json.dumps({"id": 1, "type": "event", "event": {"type": "intent-start"}})

    async def main():
        restart = asyncio.get_running_loop().create_future()
        restart.set_result(assist._Restart(0, "audio backlog"))
        return await assist._next(Late(), restart)

    message = asyncio.run(main())
    assert message is not None and message["event"]["type"] == "intent-start"


def test_an_utterance_whose_middle_was_dropped_before_its_speech_was_reported_is_a_turn_that_did_nothing():
    async def reports_late(run: Run) -> None:
        await run.heard(BLOCK)
        run.socket.flowing.clear()  # Home Assistant falls behind before it reports the speech
        await run.socket.ha.resume.wait()
        run.event("stt-vad-start", timestamp=10)
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(reports_late)
        ha.resume = asyncio.Event()
        home = listener(ha)
        home.start()
        feed(home, 0.2)
        await until(lambda: ha.runs and not ha.sockets[0].flowing.is_set())
        feed(home, assist.MAX_BACKLOG_S + 20.0)
        ha.resume.set()
        event = None
        while not isinstance(event, HomeTurn):
            event = await next_event(home)
        ha.sockets[0].flowing.set()
        home.stop()
        return event, ha

    turn, ha = asyncio.run(main())
    assert turn.outcome == Outcome.FAILED and turn.reason == "audio backlog"
    assert ha.runs[0].cancelled


# -- re-review findings ----------------------------------------------------------


def test_speech_reported_while_an_idle_restart_is_pending_voids_the_restart(monkeypatch):
    monkeypatch.setattr(assist, "IDLE_SETTLE_S", 0.1)

    async def late_vad(run: Run) -> None:
        await run.heard(int(assist.IDLE_RESTART_S * MIC_RATE))
        await asyncio.sleep(assist.IDLE_SETTLE_S + 0.05)  # the restart is set; messages are being drained
        run.event("stt-vad-start", timestamp=5800)
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(late_vad)
        home = listener(ha)
        home.start()
        feed(home, 8.0)
        await until(lambda: home._run is not None and home._run.vad_start_ms is not None)
        await asyncio.sleep(0.4)
        sent = len(ha.runs[0].samples)
        home.stop()
        return ha, drained(home), sent

    ha, events, sent = asyncio.run(main())
    # The run goes on with its turn open, and its audio flows past the idle limit.
    assert not ha.runs[0].cancelled and len(ha.run_commands) == 1
    assert [e for e in events if isinstance(e, HeardSpeech)] == [HeardSpeech(1)]
    assert sent > assist.IDLE_RESTART_S * MIC_RATE


def test_after_a_connection_lost_mid_utterance_its_rest_is_never_acted_on():
    async def lost(run: Run) -> None:
        await run.heard(BLOCK)
        run.event("stt-vad-start", timestamp=300)
        await run.heard(int(0.5 * MIC_RATE))
        run.socket.flowing.clear()  # stalls; the rest of the utterance queues
        await asyncio.sleep(0.05)
        run.socket.drop()

    async def would_act(run: Run) -> None:
        run.event("stt-vad-start", timestamp=300)
        await asyncio.sleep(0.05)
        if not run.cancelled:
            run.event("stt-vad-end", timestamp=900)
            run.intent("Done", tools=[("HassTurnOn", {"name": "light"})])

    async def main():
        ha = FakeHA(lost, would_act)
        home = listener(ha)
        home.start()
        feed(home, 0.6)
        await until(lambda: ha.runs and not ha.sockets[0].flowing.is_set())
        feed(home, 2.0)
        await until(lambda: len(ha.run_commands) == 3, limit=5)
        await settle()
        home.stop()
        return ha, drained(home)

    ha, events = asyncio.run(main())
    turns = [(e.turn, e.outcome, e.reason) for e in events if isinstance(e, HomeTurn)]
    # The rest is never acted on, and never dropped silently either: a request spoken right after is told.
    assert turns == [(1, Outcome.FAILED, "connection lost"), (2, Outcome.FAILED, "speech cut")]
    assert ha.runs[1].cancelled


def test_the_first_speech_a_backlog_gap_cuts_is_told_even_when_it_began_after_the_gap():
    async def reports_after_the_gap(run: Run) -> None:
        await run.heard(BLOCK)
        run.socket.flowing.clear()
        await run.socket.ha.resume.wait()
        # 0.2 s of the run's audio before the gap, then speech 0.2 s after it: within GAP_GUARD_S.
        await run.heard(int(0.5 * MIC_RATE))
        run.event("stt-vad-start", timestamp=400)
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(reports_after_the_gap)
        ha.resume = asyncio.Event()
        home = listener(ha)
        home.start()
        feed(home, 0.2)
        await until(lambda: ha.runs and not ha.sockets[0].flowing.is_set())
        feed(home, assist.MAX_BACKLOG_S + 20.0)
        ha.sockets[0].flowing.set()
        ha.resume.set()
        events = []
        while not any(isinstance(e, HomeTurn) for e in events):
            events.append(await next_event(home))
        home.stop()
        return events, ha

    events, ha = asyncio.run(main())
    # It may be a request of its own: GPT-Live hears that Home Assistant did nothing with it.
    assert events == [HeardSpeech(1), events[-1]]
    assert (events[-1].outcome, events[-1].reason) == (Outcome.FAILED, "audio backlog")
    assert ha.runs[0].cancelled


def test_a_short_reply_with_a_late_transcript_passes_no_echo():
    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 1.0, audible=True)  # "Sure!"
        clock.now = 0.5
        home.user_heard(None)  # the end of the user's previous utterance, transcribed late
        clock.now = 1.0
        feed(home, 0.1)
        clock.now = 1.2
        home.user_heard(None)  # still trailing, in the window after the reply
        clock.now = 1.0 + assist.BARGE_IN_WAIT_S
        feed(home, 0.4)
        await until(lambda: ha.runs and len(ha.runs[0].samples) >= int(1.4 * MIC_RATE))
        home.stop()
        return ha.runs[0].samples

    samples = asyncio.run(main())
    # Nothing of the reply reaches speech recognition: silence as long as it, then what follows it.
    assert not samples[:MIC_RATE].any() and int(samples[MIC_RATE]) == MIC_RATE


def test_a_request_right_after_a_short_reply_with_a_late_transcript_is_acted_on():
    async def acts(run: Run) -> None:
        # Silence for the reply, then the request 0.2 s after it.
        await run.heard(int(1.7 * MIC_RATE))
        run.event("stt-vad-start", timestamp=1500)
        await run.heard(int(2.5 * MIC_RATE))
        run.event("stt-vad-end", timestamp=2500)
        run.intent("Turned off the lights.", tools=[("intent__HassTurnOff", {"name": "lights"})])

    async def main():
        clock = Clock()
        ha = FakeHA(acts)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 1.0, audible=True)  # "Sure!"
        home.user_heard(None)  # trailing, not over the assistant
        clock.now = 1.0
        feed(home, 0.2)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 2.0)  # "turn off the lights"
        event = None
        while not isinstance(event, HomeTurn):
            event = await next_event(home)
        home.stop()
        return event, ha

    turn, ha = asyncio.run(main())
    assert turn.outcome == Outcome.ACTED and not ha.runs[0].cancelled


def test_an_early_interruption_reaches_home_assistant_whole():
    async def acts(run: Run) -> None:
        await run.heard(int(0.5 * MIC_RATE))
        run.event("stt-vad-start", timestamp=300)
        await run.heard(int(2.0 * MIC_RATE))
        run.event("stt-vad-end", timestamp=2000)
        run.intent("Turned off the lights.", tools=[("intent__HassTurnOff", {"name": "lights"})])

    async def main():
        clock = Clock()
        ha = FakeHA(acts)
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 0.3, audible=True)
        feed(home, 0.7, audible=True)  # "no, turn off..." from 0.3 s into the reply
        clock.now = 1.0
        home.user_heard(1.5)  # over the assistant: its transcript, as GPT-Live yields
        feed(home, 0.1)
        clock.now += assist.BARGE_IN_WAIT_S
        feed(home, 1.0)  # "...the lights"
        event = None
        while not isinstance(event, HomeTurn):
            event = await next_event(home)
        home.stop()
        return event, ha

    turn, ha = asyncio.run(main())
    assert turn.outcome == Outcome.ACTED and not ha.runs[0].cancelled
    # Whole, from the reply's start: the interruption came too early in it for any echo to be dropped.
    assert np.array_equal(ha.runs[0].samples[: 2 * MIC_RATE], counting(0, 2 * MIC_RATE))


def test_audio_queued_during_a_long_intent_stage_is_never_dropped(monkeypatch):
    # The idle restart is out of the way: this is about the backlog alone.
    monkeypatch.setattr(assist, "IDLE_RESTART_S", 100.0)

    async def slow_agent(run: Run) -> None:
        await run.heard(BLOCK)
        run.speech(start_ms=0, end_ms=10)
        run.event("stt-end", stt_output={"text": "turn on the kitchen light"})
        run.event("intent-start")
        await run.socket.ha.release.wait()  # the agent's tool calls take a while
        run.intent("Turned on the kitchen light.", tools=[("intent__HassTurnOn", {"area": "Kitchen"})])

    async def next_request(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(slow_agent, next_request)
        ha.release = asyncio.Event()
        home = listener(ha)
        home.start()
        feed(home, 0.1)
        await until(lambda: home._run is not None and home._run.intent_started)
        # Longer than the old 10 s bound: "...and the fan", while Home Assistant is busy.
        feed(home, 30.0)
        ha.release.set()
        await until(lambda: len(ha.runs) == 2 and len(ha.runs[1].samples) >= 30 * MIC_RATE, limit=10)
        home.stop()
        return ha, drained(home)

    ha, events = asyncio.run(main())
    assert not any(isinstance(e, HomeTurn) and e.reason == "audio backlog" for e in events)
    # The next run hears all of it, in order, from the first run's end of speech on.
    assert np.array_equal(ha.runs[1].samples[: 30 * MIC_RATE], counting(10 * MS, 30 * MIC_RATE))


def test_a_wall_clock_idle_restart_waits_for_home_assistants_verdict_on_audio_just_sent(monkeypatch):
    monkeypatch.setattr(assist, "IDLE_RUN_AGE_S", 0.5)
    monkeypatch.setattr(assist, "IDLE_SETTLE_S", 0.2)

    async def speech_reported_a_moment_later(run: Run) -> None:
        await run.heard(int(2.0 * MIC_RATE))
        await run.socket.ha.resume.wait()
        await asyncio.sleep(0.05)
        run.event("stt-vad-start", timestamp=1200)
        run.event("stt-vad-end", timestamp=1900)
        run.intent("Done", tools=[("HassTurnOn", {"name": "light"})])

    async def main():
        clock = Clock()
        ha = FakeHA(speech_reported_a_moment_later)
        ha.resume = asyncio.Event()
        home = listener(ha, clock=clock)
        home.start()
        feed(home, 2.0)  # a burst, as after the assistant: speech in it, not yet reported
        await until(lambda: ha.runs and len(ha.runs[0].samples) >= 2 * MIC_RATE)
        clock.now = 1.0  # the run is past its wall-clock age
        feed(home, 0.01)
        ha.resume.set()
        event = None
        while not isinstance(event, HomeTurn):
            event = await next_event(home)
        home.stop()
        return ha, event

    ha, turn = asyncio.run(main())
    assert turn.outcome == Outcome.ACTED and not ha.runs[0].cancelled


# -- review of the hold (2026-10-17) -------------------------------------------------


def feed_timed(home: HomeListener, clock: Clock, seconds: float, audible: bool = False) -> None:
    """Audio as it comes in: the listener's clock moves on with it."""
    for _ in range(int(seconds * 100)):
        home.feed(counting(home._next_index, BLOCK), audible)
        clock.now += 0.01


def _late(after_end_of_speech: bool):
    async def acts_on_the_rest(run: Run) -> None:
        # "...the kitchen light", after the assistant yields: speech from the release on.
        await run.heard(int(1.5 * MIC_RATE))
        if not after_end_of_speech:
            await run.socket.ha.reported.wait()
        run.event("stt-vad-start", timestamp=1300)
        if after_end_of_speech:
            await run.heard(int(2.0 * MIC_RATE))
            run.event("stt-vad-end", timestamp=2000)
            await run.socket.ha.reported.wait()
        await asyncio.sleep(0.05)
        if not run.cancelled:
            run.event("stt-vad-end", timestamp=2500)
            run.intent("Done", tools=[("HassTurnOff", {"name": "kitchen light"})])

    async def main():
        clock = Clock()
        ha = FakeHA(acts_on_the_rest)
        ha.reported = asyncio.Event()
        home = listener(ha, clock=clock)
        home.start()
        feed_timed(home, clock, 1.0, audible=True)  # "turn off", over the assistant's last second
        # Decided as echo: nothing was reported over the assistant within BARGE_IN_WAIT_S.
        feed_timed(home, clock, assist.BARGE_IN_WAIT_S + 0.2)
        if after_end_of_speech:
            await until(lambda: home._run is not None and home._run.audio_done)
        # GPT-Live's transcript of "turn off" comes late, stamped within the assistant's speech, with the
        # age live.py gives a fragment of its own: the minimum, whatever the real lag was.
        home.user_heard(2.5, during=True)
        ha.reported.set()
        events = []
        while not any(isinstance(e, HomeTurn) for e in events):
            events.append(await next_event(home))
        home.stop()
        return events, ha

    return asyncio.run(main())


def test_speech_over_the_assistant_reported_after_the_decision_cuts_its_rest_and_tells_it():
    events, ha = _late(after_end_of_speech=False)
    # Never acted on in part, and told: the user hears it did not happen.
    assert (events[-1].outcome, events[-1].reason) == (Outcome.FAILED, "speech cut")
    assert ha.runs[0].cancelled


def test_speech_over_the_assistant_reported_after_home_assistant_heard_its_rest_end_is_told_as_uncertain():
    events, _ = _late(after_end_of_speech=True)
    # Too late to stop: it may have acted on the rest alone, and the user is told to check.
    assert (events[-1].outcome, events[-1].reason) == (Outcome.UNCERTAIN, "speech cut late")


def test_later_transcripts_of_speech_over_the_assistant_already_passed_on_cut_nothing():
    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        feed_timed(home, clock, 1.0, audible=True)
        home.user_heard(2.5, during=True)  # "no, turn off..." over the assistant, which yields
        feed_timed(home, clock, assist.BARGE_IN_WAIT_S + 0.2)  # "...the kitchen light"
        home.user_heard(2.5, during=True)  # more of the same speech, transcribed after the decision
        return home

    home = asyncio.run(main())
    assert not home._overrun and home._gap_at is None


def test_a_transcript_just_after_the_assistant_never_cuts_a_quick_follow_up():
    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        feed_timed(home, clock, 1.0, audible=True)  # "Done."
        feed_timed(home, clock, assist.BARGE_IN_WAIT_S + 0.2)  # "and the fan", right after it
        # Stamped after the assistant's speech: it may be this new request, which is heard as usual.
        home.user_heard(2.5, during=False)
        return home

    home = asyncio.run(main())
    assert not home._overrun and home._gap_at is None


def test_speech_over_the_assistant_older_than_the_audio_kept_for_it_is_never_acted_on_in_part():
    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        clock = Clock()
        ha = FakeHA(listens)
        home = listener(ha, clock=clock)
        feed(home, 8.0, audible=True)
        home.user_heard(6.0)  # past BARGE_IN_BACK_MAX_S
        return home

    home = asyncio.run(main())
    keep_from = int((8.0 - assist.BARGE_IN_BACK_MAX_S - assist.BARGE_IN_PREROLL_S) * MIC_RATE)
    assert home._overrun and (home._gap_at, home._gap_reason) == (keep_from, "speech cut")


def test_a_pause_pushed_out_of_a_long_hold_goes_on_and_cancels_nothing(monkeypatch):
    monkeypatch.setattr(assist, "HOLD_MAX_S", 2.0)

    async def listens(run: Run) -> None:
        await asyncio.Event().wait()

    async def main():
        ha = FakeHA(listens)
        home = listener(ha, clock=Clock())
        feed(home, 0.5, audible=True)
        feed(home, 0.3)  # the user speaks in a pause, undecided
        feed(home, 3.0, audible=True)  # the assistant again, long enough to push the pause out
        return home

    home = asyncio.run(main())
    # Released as if no one spoke over the assistant: the pause's audio goes on, between silences.
    queued = np.concatenate([f.pcm for f in home._queue])
    assert np.array_equal(queued[MIC_RATE // 2 : int(0.8 * MIC_RATE)], counting(MIC_RATE // 2, int(0.3 * MIC_RATE)))
    assert not queued[: MIC_RATE // 2].any() and not home._overrun


def test_a_late_backchannel_over_the_reply_never_cancels_the_request_before_it():
    async def acts(run: Run) -> None:
        await run.heard(int(0.5 * MIC_RATE))
        run.event("stt-vad-start", timestamp=300)
        await run.socket.ha.reported.wait()
        run.event("stt-vad-end", timestamp=1300)
        run.intent("Turned on the kitchen light.", tools=[("intent__HassTurnOn", {"area": "Kitchen"})])

    async def main():
        clock = Clock()
        ha = FakeHA(acts)
        ha.reported = asyncio.Event()
        home = listener(ha, clock=clock)
        home.start()
        feed_timed(home, clock, 0.6)  # "turn on the kitchen light"
        await until(lambda: home._run is not None and home._run.vad_start_ms is not None)
        # GPT-Live answers before Home Assistant heard the end; "thanks" over it is transcribed late.
        feed_timed(home, clock, 1.0, audible=True)
        feed_timed(home, clock, assist.BARGE_IN_WAIT_S + 0.2)
        home.user_heard(2.5, during=True)
        ha.reported.set()
        event = None
        while not isinstance(event, HomeTurn):
            event = await next_event(home)
        home.stop()
        return event, ha

    turn, ha = asyncio.run(main())
    # Not cancelled; and, as it may have gone on into the reply, told as possibly done in part.
    assert not ha.runs[0].cancelled
    assert (turn.outcome, turn.reason) == (Outcome.UNCERTAIN, "speech cut late")


def test_late_transcripts_of_one_speech_make_one_gap():
    async def main():
        clock = Clock()
        home = listener(FakeHA(), clock=clock)
        feed_timed(home, clock, 1.0, audible=True)
        feed_timed(home, clock, assist.BARGE_IN_WAIT_S + 0.2)
        home.user_heard(2.5, during=True)
        home.user_heard(2.5, during=True)
        return home

    home = asyncio.run(main())
    assert home._gaps == 1
