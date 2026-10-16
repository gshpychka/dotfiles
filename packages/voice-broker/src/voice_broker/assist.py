"""Home Assistant's Assist pipeline on the conversation's own audio, from speech to intent.

Home Assistant alone acts on the home. It hears every utterance at the speaker,
as the same echo-cancelled audio GPT-Live hears, through its own speech
recognition, end-of-speech detection and conversation agent. GPT-Live only
speaks the result. Each utterance is one `assist_pipeline/run` from the stt
stage to the intent stage. Source is home-assistant/core 2026.10.1, the version
the household runs; the paths below are under homeassistant/components/assist_pipeline/.

- Wire format (websocket_api.py, websocket_api/http.py):
  - The run's `run-start` event carries runner_data.stt_binary_handler_id.
  - Audio is binary messages of that one-byte id followed by PCM16 mono at 16 kHz,
    sent after `run-start`.
  - A message of the id alone ends the audio. The broker never sends it: Home
    Assistant's own VAD ends each utterance (below).
- End of speech (default_pipeline.py, vad.py):
  - VoiceCommandSegmenter runs, because the STT provider requires an external VAD.
    That is the stt default, and openai_whisper_cloud keeps it.
  - It starts after 0.3 s of speech and ends after 0.7 s of silence, and reports
    both as `stt-vad-start`/`stt-vad-end` with a timestamp in ms of the run's audio.
  - Its 15 s timeout counts all of a run's audio. With no speech it would hand
    15 s of silence to Whisper, which can hallucinate words from silence. So a
    run that has heard no speech is cancelled and started afresh before then
    (_IDLE_RESTART_S), keeping the newest second, in which speech may be starting.
    A run whose VAD ends without having started is cancelled the same way.
- Ordering: the runs of a conversation follow each other on one connection,
  never overlapping, so home turns are serialized. The next run starts after
  the previous `run-end`, and audio arriving meanwhile waits for it. A run also
  holds its device's lock, so a new conversation's run waits for the old one's
  to finish.
- Cancellation: a run is cancelled (`unsubscribe_events`, or closing the socket)
  only before `intent-start`, because until then nothing has acted. From
  `intent-start` on, a run is waited out and never cancelled or retried: a tool
  call that started finishes even when its run is cancelled (conversation/chat_log.py).
  Nor is a run cancelled once Home Assistant has its whole utterance (stt-vad-end):
  the intent stage may already be starting.
- Lost audio: a backlog past MAX_BACKLOG_S drops its oldest audio. Speech that may
  have lost its start or middle to such a gap is never acted on: its run is
  cancelled at stt-vad-start, and the gap moves past it, so the rest of the same
  utterance is cancelled the same way (GAP_GUARD_S).
- Echo: speech recognition gets no audio while the assistant is audible, as on
  Home Assistant's own satellites, so GPT-Live's echo cannot become a command;
  see feed(). A barge-in passes the last held second on, but only a transcript
  that comes BARGE_IN_GRACE_S into the assistant's speech counts as one: an
  earlier one trails the user's previous utterance.
"""

from __future__ import annotations

import asyncio
import contextlib
import enum
import json
import logging
import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import numpy as np
from websockets.asyncio.client import connect
from websockets.exceptions import WebSocketException

from .protocol import MIC_RATE

log = logging.getLogger(__name__)

# Home Assistant's limit on one run: waiting for speech, recognition and the agent's tool calls.
RUN_TIMEOUT_S = 60
# Ours, just outside it, so Home Assistant's own timeout error arrives first.
_RUN_DEADLINE_S = RUN_TIMEOUT_S + 5
# Audio without speech after which a run starts afresh, inside the segmenter's 15 s timeout.
# What is left of that timeout after a restart bounds the longest command: 15 - 6 + 1 s at least.
IDLE_RESTART_S = 6.0
# Audio kept for the next run when an idle run restarts: speech may be starting in it.
RESTART_KEEP_S = 1.0
# Once IDLE_RESTART_S has been sent without speech, the sender waits this long for Home Assistant's
# verdict on it before restarting: a backlog goes out at socket speed, far ahead of stt-vad-start.
IDLE_SETTLE_S = 1.0
# Wall time after which a run that has heard no speech starts afresh, inside Home Assistant's own
# RUN_TIMEOUT_S, which is wall time too: while the assistant is audible no audio is sent at all.
IDLE_RUN_AGE_S = RUN_TIMEOUT_S - 15.0
# Speech Home Assistant detects within this much audio after a gap in the queue may be the rest of an
# utterance whose start was dropped; such a run is cancelled before it can act on part of the utterance.
GAP_GUARD_S = 1.0
# Audio queued for Home Assistant at most. A connection this far behind drops the oldest,
# and a run that loses audio of its utterance is cancelled before it can act on part of it.
MAX_BACKLOG_S = 10.0
# After the assistant stops being audible, how long to wait for GPT-Live to report the user
# speaking over it (a barge-in) before the held audio is dropped.
BARGE_IN_WAIT_S = 0.5
# Audio from the end of the assistant's speech that a barge-in passes on. It holds
# the user's first words, and the last of the echo-cancelled assistant audio.
BARGE_IN_KEEP_S = 1.0
# GPT-Live's transcript trails the speech, so a transcript this soon after the assistant became audible
# is taken for the end of the user's previous utterance, not for speech over the assistant.
BARGE_IN_GRACE_S = 1.5
# Before a run is cancelled, messages already on their way are read for this long: one may be intent-start.
_DRAIN_S = 0.2
# Speech the segmenter needs before stt-vad-start (vad.py VoiceCommandSegmenter.speech_seconds).
_MIN_SPEECH_MS = 300
# Connecting, authenticating and resolving the pipeline.
_SETUP_TIMEOUT_S = 10.0
# Waiting for Home Assistant to confirm a command.
_REPLY_TIMEOUT_S = 10.0
# Lost connections a conversation reconnects after, before it gives up on Home Assistant.
_MAX_RECONNECTS = 2
_SAMPLES_PER_MS = MIC_RATE // 1000


class Outcome(enum.StrEnum):
    """What a run did, from its own evidence; a generic `action_done` proves nothing."""

    # Changed or tried to change the home: a tool that is not read-only, or a local intent with targets.
    ACTED = "acted"
    # Waits on the user's answer, in the same Home Assistant conversation.
    ASKED = "asked"
    # Answered from the home's state, with read-only tools only.
    ANSWERED = "answered"
    # Nothing for the home: the speech was not a home request.
    ABSTAINED = "abstained"
    # Stopped before the intent stage, so nothing was done.
    FAILED = "failed"
    # Stopped after the intent stage began: it may have acted.
    UNCERTAIN = "uncertain"


@dataclass(frozen=True, slots=True)
class ToolUse:
    name: str
    args: Any
    # None: no result was reported.
    failed: bool | None = None
    # Run at the LLM's provider, such as its web search.
    external: bool = False


@dataclass(frozen=True, slots=True)
class HomeTurn:
    """One run's result: what Home Assistant heard, did and said."""

    # Run counter within the conversation, the broker's own turn ID.
    turn: int
    outcome: Outcome
    # What Home Assistant says: its reply, or its question. Empty when it had nothing to say.
    speech: str
    # Home Assistant's own transcript; None before speech recognition finished.
    heard: str | None
    tools: tuple[ToolUse, ...] = ()
    # Where its VAD heard the utterance start and end, as MIC_RATE sample indexes of the
    # conversation's audio. None when it was not reported.
    speech_start: int | None = None
    speech_end: int | None = None
    # A Home Assistant error code or the broker's own reason; never a message.
    reason: str = ""
    # Its speech is a question Home Assistant waits on, whatever else the turn did.
    asks: bool = False


@dataclass(frozen=True, slots=True)
class HeardSpeech:
    """A run heard speech start: its HomeTurn follows."""

    turn: int


@dataclass(frozen=True, slots=True)
class Unavailable:
    """Home Assistant is out for the rest of the conversation."""

    reason: str


HomeEvent = HeardSpeech | HomeTurn | Unavailable


@dataclass(frozen=True, slots=True)
class ToolPolicy:
    """How a tool call counts as evidence, by its name after the last "__" (e.g. intent__HassTurnOn)."""

    # Tools that only read the home.
    read_only: frozenset[str]
    # Tools that do work that is not about the home, such as asking another LLM.
    non_home: frozenset[str]

    def kind(self, tool: ToolUse) -> str:
        base = tool.name.rsplit("__", 1)[-1]
        if tool.external or base in self.non_home:
            return "non_home"
        return "read" if base in self.read_only else "action"


class _Unusable(Exception):
    """Home Assistant can't take audio for this conversation."""


class _Lost(Exception):
    """The connection ended or stopped answering."""


@dataclass(frozen=True, slots=True)
class _Restart:
    """Cancels a run before its intent stage, keeping its newest `keep` samples for the next."""

    keep: int
    # Reported as a failed turn when set; an idle restart is not a turn.
    reason: str = ""
    # The kept audio may continue an utterance whose start is gone: a gap is marked before it.
    gap: bool = False


@dataclass(frozen=True, slots=True)
class _Frame:
    # MIC_RATE sample index of its first sample in the conversation's audio.
    index: int
    pcm: np.ndarray


@dataclass
class _Run:
    turn: int
    # The listener's clock when the run was started.
    started: float = 0.0
    # (run audio offset in samples, frame) of every frame sent, in order.
    sent: list[tuple[int, _Frame]] = field(default_factory=list)
    sent_samples: int = 0
    # VAD timestamps, ms of run audio.
    vad_start_ms: int | None = None
    vad_end_ms: int | None = None
    # Conversation sample indexes of the same.
    speech_start: int | None = None
    speech_end: int | None = None
    # Its audio is complete: the sender stopped.
    audio_done: bool = False
    heard: str | None = None
    intent_started: bool = False
    tools: list[ToolUse] = field(default_factory=list)
    output: dict[str, Any] | None = None
    processed_locally: bool = False
    error: str | None = None

    def index_at(self, ms: int) -> int | None:
        """The conversation sample index at `ms` of run audio."""
        offset = ms * _SAMPLES_PER_MS
        for start, frame in reversed(self.sent):
            if start <= offset:
                return frame.index + min(offset - start, len(frame.pcm))
        return None

    def sent_from(self, offset: int) -> list[_Frame]:
        """The sent audio from run audio `offset` samples on."""
        frames: list[_Frame] = []
        for start, frame in self.sent:
            if start + len(frame.pcm) <= offset:
                continue
            cut = max(0, offset - start)
            frames.append(_Frame(frame.index + cut, frame.pcm[cut:]))
        return frames


class HomeListener:
    """Home Assistant listening at one speaker for one conversation.

    The conversation feeds audio with feed(), which never blocks. start() talks to
    Home Assistant in a task, and its results arrive on `events`.
    """

    def __init__(
        self,
        url: str,
        token: str,
        pipeline: str,
        device_id: str,
        policy: ToolPolicy,
        lock: asyncio.Lock,
        connector: Callable[..., Any] = connect,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        parts = urlsplit(url)
        self._url = urlunsplit(("wss" if parts.scheme == "https" else "ws", parts.netloc, "/api/websocket", "", ""))
        self._token = token
        # The pipeline's name: the broker's pipeline is created by name in Home Assistant (runbook).
        self._pipeline_name = pipeline
        self._pipeline_id: str | None = None
        # The Voice PE's ESPHome device: Home Assistant resolves its area and unplaced requests by it.
        self._device_id = device_id
        self._policy = policy
        # This device's: runs of all its conversations take turns.
        self._lock = lock
        self._connect = connector
        self._clock = clock
        self.events: asyncio.Queue[HomeEvent] = asyncio.Queue()

        self._next_index = 0
        self._queue: deque[_Frame] = deque()
        self._queued = 0
        self._wake = asyncio.Event()
        # Audio was dropped from the queue since the speech of the run in progress was checked against it.
        self._overrun = False
        # Conversation sample index of the first audio after the newest gap in what Home Assistant
        # hears: audio dropped from the queue, or the rest of an utterance a run was cancelled for.
        self._gap_at: int | None = None
        # The assistant is audible: audio is held, not sent.
        self._holding = False
        self._holding_since = 0.0
        self._held: deque[_Frame] = deque()
        self._held_samples = 0
        # The assistant stopped being audible: audio waits until a barge-in is ruled in or out.
        self._deciding_until: float | None = None
        self._undecided: list[_Frame] = []
        self._barged_in = False

        self._msg_id = 0
        self._turns = 0
        # Home Assistant's conversation at this speaker, continued by every run of this conversation.
        self._conversation_id: str | None = None
        self._run: _Run | None = None
        # Set once the conversation ends: no new run starts.
        self._stopping = False
        self._task: asyncio.Task[None] | None = None

    # -- audio in ------------------------------------------------------------

    def feed(self, pcm: np.ndarray, audible: bool) -> None:
        """One block of echo-cancelled MIC_RATE audio, and whether the assistant was audible meanwhile."""
        frame = _Frame(self._next_index, pcm)
        self._next_index += len(pcm)
        if audible:
            if not self._holding:
                if self._deciding_until is not None:
                    # The assistant speaks again before the last pause was decided: what the
                    # pause held was heard while it was silent, so it goes on.
                    self._decide()
                self._holding = True
                self._holding_since = self._clock()
                self._barged_in = False
                self._held.clear()
                self._held_samples = 0
            self._held.append(frame)
            self._held_samples += len(pcm)
            while self._held_samples - len(self._held[0].pcm) >= BARGE_IN_KEEP_S * MIC_RATE:
                self._held_samples -= len(self._held.popleft().pcm)
            return
        if self._holding:
            self._holding = False
            self._deciding_until = self._clock() + BARGE_IN_WAIT_S
            self._undecided = []
        if self._deciding_until is not None:
            self._undecided.append(frame)
            if self._barged_in or self._clock() >= self._deciding_until:
                self._decide()
            return
        self._enqueue(frame)

    def user_heard(self) -> None:
        """GPT-Live heard the user speak; over the assistant, while audio is held."""
        if self._clock() - self._holding_since < BARGE_IN_GRACE_S:
            # Most likely the transcript of what the user said before the assistant began: letting it
            # count would hand the assistant's own echo to speech recognition.
            return
        if self._holding or self._deciding_until is not None:
            self._barged_in = True
            if self._deciding_until is not None:
                self._decide()

    def _decide(self) -> None:
        """Passes on the held audio after a barge-in, or drops it, then everything after it."""
        if self._barged_in:
            log.info("barge-in: passing %.1f s of held audio to home assistant", self._held_samples / MIC_RATE)
            for frame in self._held:
                self._enqueue(frame)
        self._held.clear()
        self._held_samples = 0
        self._deciding_until = None
        self._barged_in = False
        for frame in self._undecided:
            self._enqueue(frame)
        self._undecided = []

    def _enqueue(self, frame: _Frame) -> None:
        self._queue.append(frame)
        self._queued += len(frame.pcm)
        while self._queued > MAX_BACKLOG_S * MIC_RATE:
            self._queued -= len(self._queue.popleft().pcm)
            self._overrun = True
            self._gap_at = self._queue[0].index
        self._wake.set()

    def _gap_ahead(self) -> None:
        """Marks a gap before the audio not yet sent: what comes next may continue a cut utterance."""
        self._gap_at = self._queue[0].index if self._queue else self._next_index

    def _cut(self, run: _Run) -> bool:
        """Whether `run`'s speech may have lost its start or its middle to a gap."""
        if self._gap_at is None or not run.sent:
            return False
        start = run.speech_start if run.speech_start is not None else run.sent[0][1].index
        return start - self._gap_at < GAP_GUARD_S * MIC_RATE

    def _past_speech_start(self, run: _Run, reason: str = "") -> _Restart:
        """Cancels a run whose speech may be cut, keeping what it sent from that speech's detection on.

        The kept audio may be more of the same utterance, so a gap goes before it; or a later
        utterance, which is not lost. It moves at least _MIN_SPEECH_MS on each time, so the
        rest of a long utterance is cancelled piece by piece until a pause.
        """
        start_ms = max(run.vad_start_ms or 0, _MIN_SPEECH_MS)
        return _Restart(max(0, run.sent_samples - start_ms * _SAMPLES_PER_MS), reason, gap=True)

    def _requeue(self, frames: list[_Frame]) -> None:
        """Audio a run did not use, back at the front of the queue, in order."""
        for frame in reversed(frames):
            if len(frame.pcm):
                self._queue.appendleft(frame)
                self._queued += len(frame.pcm)
        self._wake.set()

    # -- lifecycle -----------------------------------------------------------

    def start(self) -> None:
        self._task = asyncio.create_task(self._serve(), name="home-assistant")

    def stop(self) -> asyncio.Task[None] | None:
        """Ends listening: a run that may act is waited out in the background, any other is cancelled.

        Returns the task still finishing such a run; awaiting it is optional.
        """
        self._stopping = True
        self._wake.set()
        task = self._task
        if task is None or task.done():
            return None
        if self._run is not None and self._run.intent_started:
            log.info("conversation over during home assistant turn %d; letting it finish", self._run.turn)
            return task
        task.cancel()
        return None

    async def _serve(self) -> None:
        reconnects = 0
        while not self._stopping:
            try:
                async with asyncio.timeout(_SETUP_TIMEOUT_S):
                    ws = await self._connect(self._url, max_size=2**22, open_timeout=_SETUP_TIMEOUT_S)
            except (TimeoutError, OSError, WebSocketException) as e:
                if not await self._lost(f"connect: {type(e).__name__}", reconnects):
                    return
                reconnects += 1
                continue
            try:
                await self._session(ws)
                return
            except _Unusable as e:
                log.warning("home assistant unusable: %s", e)
                self.events.put_nowait(Unavailable(str(e)))
                return
            except (_Lost, OSError, WebSocketException, TimeoutError, ValueError, TypeError) as e:
                if not await self._lost(type(e).__name__, reconnects):
                    return
                reconnects += 1
            except Exception as e:  # a bug must not leave the conversation waiting on a turn
                log.exception("home assistant listener failed")
                run, self._run = self._run, None
                if run is not None:
                    # Uncertain once its intent stage began: _turn decides, from what the run reached.
                    self._finish(run, f"internal {type(e).__name__}")
                self.events.put_nowait(Unavailable("internal error"))
                return
            finally:
                await ws.close()

    async def _lost(self, reason: str, reconnects: int) -> bool:
        """Reports the run a lost connection cut off; whether to connect again."""
        run, self._run = self._run, None
        if run is not None:
            # Lost before intent-start: Home Assistant cancelled the run with the connection.
            self._finish(run, "connection lost")
        if self._stopping:
            return False
        if reconnects >= _MAX_RECONNECTS:
            log.warning("home assistant lost for good: %s", reason)
            self.events.put_nowait(Unavailable("connection lost"))
            return False
        log.warning("home assistant connection lost (%s); reconnecting", reason)
        await asyncio.sleep(0.5 * (reconnects + 1))
        return True

    async def _session(self, ws: Any) -> None:
        async with asyncio.timeout(_SETUP_TIMEOUT_S):
            if _message(await ws.recv()).get("type") != "auth_required":
                raise _Unusable("no auth_required")
            await ws.send(json.dumps({"type": "auth", "access_token": self._token}))
            if _message(await ws.recv()).get("type") != "auth_ok":
                raise _Unusable("authentication refused")
            if self._pipeline_id is None:
                self._pipeline_id = await self._resolve_pipeline(ws)
        while not self._stopping:
            async with self._lock:
                if self._stopping:
                    return
                await self._one_run(ws)

    async def _resolve_pipeline(self, ws: Any) -> str:
        result = await self._command(ws, {"type": "assist_pipeline/pipeline/list"})
        pipelines = result.get("pipelines") if isinstance(result, dict) else None
        if not isinstance(pipelines, list):
            raise _Unusable("pipeline list without pipelines")
        matches = [p.get("id") for p in pipelines if isinstance(p, dict) and p.get("name") == self._pipeline_name]
        if len(matches) != 1 or not isinstance(matches[0], str):
            raise _Unusable(f"{len(matches)} pipelines named {self._pipeline_name!r}")
        return matches[0]

    def _id(self) -> int:
        self._msg_id += 1
        return self._msg_id

    async def _command(self, ws: Any, command: dict[str, Any]) -> Any:
        """A one-shot command's result; events of a cancelled run arriving meanwhile are skipped."""
        msg_id = self._id()
        await ws.send(json.dumps({"id": msg_id, **command}))
        async with asyncio.timeout(_REPLY_TIMEOUT_S):
            while True:
                message = _message(await ws.recv())
                if message.get("id") == msg_id and message.get("type") == "result":
                    if not message.get("success"):
                        raise _Unusable(f"{command['type']} refused: {(message.get('error') or {}).get('code')}")
                    return message.get("result")

    # -- one run -------------------------------------------------------------

    async def _one_run(self, ws: Any) -> None:
        self._turns += 1
        run = _Run(self._turns, self._clock())
        run_id = self._id()
        command: dict[str, Any] = {
            "id": run_id,
            "type": "assist_pipeline/run",
            "start_stage": "stt",
            "end_stage": "intent",
            "input": {"sample_rate": MIC_RATE},
            "pipeline": self._pipeline_id,
            "device_id": self._device_id,
            "timeout": RUN_TIMEOUT_S,
        }
        if self._conversation_id is not None:
            command["conversation_id"] = self._conversation_id
        self._run = run
        restart: asyncio.Future[_Restart] = asyncio.get_running_loop().create_future()
        sender: asyncio.Task[None] | None = None
        await ws.send(json.dumps(command))
        try:
            async with asyncio.timeout(_RUN_DEADLINE_S):
                while True:
                    # Past the end of its audio, Home Assistant may start the intent stage any moment, and an
                    # intent stage under way is never cancelled: the run is waited out.
                    message = await _next(ws, None if run.intent_started or run.audio_done else restart)
                    if message is None:
                        await _stopped(sender)
                        sender = None
                        await self._restart(ws, run, run_id, restart.result())
                        return
                    if message.get("id") != run_id:
                        continue
                    if message.get("type") == "result":
                        if not message.get("success"):
                            # A pipeline deleted since it was resolved, or a run refused outright.
                            raise _Unusable(f"run refused: {(message.get('error') or {}).get('code')}")
                        continue
                    event = message.get("event")
                    event = event if isinstance(event, dict) else {}
                    data = event.get("data")
                    kind, data = event.get("type"), data if isinstance(data, dict) else {}
                    if kind == "run-start":
                        handler = (data.get("runner_data") or {}).get("stt_binary_handler_id")
                        if not isinstance(handler, int) or not 0 <= handler <= 255:
                            raise _Unusable("run-start without an audio handler")
                        sender = asyncio.create_task(self._send_audio(ws, run, handler, restart))
                        continue
                    if kind == "run-end":
                        break
                    self._on_event(run, kind, data)
                    if kind == "stt-vad-start" and not run.intent_started:
                        if self._cut(run):
                            # Never acted on. An utterance that lost its middle is a turn that did nothing;
                            # the rest of one whose start is gone is no turn of its own.
                            assert self._gap_at is not None
                            lost_middle = run.speech_start is not None and run.speech_start <= self._gap_at
                            await _stopped(sender)
                            sender = None
                            reason = "audio backlog" if lost_middle else ""
                            await self._restart(ws, run, run_id, self._past_speech_start(run, reason))
                            return
                        # Audio dropped before this speech began is no part of it.
                        self._overrun = False
                        self.events.put_nowait(HeardSpeech(run.turn))
                    if kind == "stt-vad-end" and run.vad_start_ms is None and not run.intent_started:
                        # The segmenter timed out without speech: never let Whisper's take on silence act.
                        await _stopped(sender)
                        sender = None
                        await self._restart(ws, run, run_id, _Restart(int(RESTART_KEEP_S * MIC_RATE)))
                        return
                    if run.audio_done and sender is not None:
                        await _stopped(sender)
                        sender = None
                        if run.vad_end_ms is not None:
                            # Audio past the end of speech belongs to the next utterance.
                            self._requeue(run.sent_from(run.vad_end_ms * _SAMPLES_PER_MS))
        except TimeoutError:
            raise _Lost(f"run {run.turn} past {_RUN_DEADLINE_S} s") from None
        finally:
            await _stopped(sender)
        self._run = None
        self._finish(run)

    async def _restart(self, ws: Any, run: _Run, run_id: int, restart: _Restart) -> None:
        """Cancels `run`, which has not reached its intent stage, so nothing ran.

        Its sender has stopped, so run.sent is final: what it holds past the kept audio is requeued.
        """
        await ws.send(json.dumps({"id": self._id(), "type": "unsubscribe_events", "subscription": run_id}))
        self._requeue(run.sent_from(max(0, run.sent_samples - restart.keep)))
        if restart.gap:
            self._gap_ahead()
        self._run = None
        if restart.reason:
            self._finish(run, restart.reason)

    def _on_event(self, run: _Run, kind: Any, data: dict[str, Any]) -> None:
        match kind:
            case "stt-vad-start":
                run.vad_start_ms = _ms(data)
                run.speech_start = run.index_at(run.vad_start_ms)
            case "stt-vad-end":
                run.vad_end_ms = _ms(data)
                run.speech_end = run.index_at(run.vad_end_ms)
                run.audio_done = True
            case "stt-end":
                run.heard = str((data.get("stt_output") or {}).get("text") or "")
                run.audio_done = True
                log.info("home assistant heard: %s", run.heard)
            case "intent-start":
                run.intent_started = True
            case "intent-progress":
                delta = data.get("chat_log_delta")
                if isinstance(delta, dict):
                    _record(run, delta)
            case "intent-end":
                run.processed_locally = data.get("processed_locally") is True
                output = data.get("intent_output")
                run.output = output if isinstance(output, dict) else {}
                conversation_id = run.output.get("conversation_id")
                if isinstance(conversation_id, str) and conversation_id:
                    self._conversation_id = conversation_id
            case "error":
                run.error = str(data.get("code") or "unknown")
                log.warning("home assistant turn %d error: %s", run.turn, run.error)

    async def _send_audio(self, ws: Any, run: _Run, handler: int, restart: asyncio.Future[_Restart]) -> None:
        prefix = bytes([handler])
        idle = _Restart(int(RESTART_KEEP_S * MIC_RATE))
        while not self._stopping:
            age = self._clock() - run.started
            if run.vad_start_ms is None and age >= IDLE_RUN_AGE_S:
                restart.set_result(idle)
                return
            if not self._queue:
                self._wake.clear()
                if run.vad_start_ms is None:
                    # Bounded, so the run's age is checked while the assistant is audible and nothing comes.
                    with contextlib.suppress(TimeoutError):
                        await asyncio.wait_for(self._wake.wait(), IDLE_RUN_AGE_S - age)
                else:
                    await self._wake.wait()
                continue
            if self._overrun and run.speech_start is not None and not run.intent_started:
                # Part of this utterance was dropped: never act on the rest.
                restart.set_result(self._past_speech_start(run, "audio backlog"))
                return
            frame = self._queue.popleft()
            self._queued -= len(frame.pcm)
            run.sent.append((run.sent_samples, frame))
            run.sent_samples += len(frame.pcm)
            await ws.send(prefix + frame.pcm.astype("<i2").tobytes())
            if run.vad_start_ms is None and run.sent_samples >= IDLE_RESTART_S * MIC_RATE:
                # Sent is not heard yet: a backlog goes out far faster than Home Assistant reports on it.
                await asyncio.sleep(IDLE_SETTLE_S)
                if run.vad_start_ms is None:
                    restart.set_result(idle)
                    return

    def _finish(self, run: _Run, reason: str = "") -> None:
        turn = _turn(run, self._policy, reason)
        log.log(
            logging.WARNING if turn.outcome == Outcome.UNCERTAIN else logging.INFO,
            "home assistant turn %d: %s%s%s",
            turn.turn,
            turn.outcome,
            f" ({turn.reason})" if turn.reason else "",
            f" tools={[t.name for t in turn.tools]}" if turn.tools else "",
        )
        if run.vad_start_ms is None and turn.outcome in (Outcome.FAILED, Outcome.ABSTAINED):
            # Nothing was said: a false wake, noise, or a run cut short before speech.
            return
        if turn.speech:
            log.info("home assistant -> %s", turn.speech)
        self.events.put_nowait(turn)


async def _stopped(sender: asyncio.Task[None] | None) -> None:
    """Stops a run's sender; once this returns, the run's sent audio no longer grows."""
    if sender is not None:
        sender.cancel()
        await asyncio.gather(sender, return_exceptions=True)


async def _next(ws: Any, restart: asyncio.Future[_Restart] | None) -> dict[str, Any] | None:
    """The next message, or None once `restart` is set first."""
    if restart is None:
        return _message(await ws.recv())
    receive = asyncio.ensure_future(ws.recv())
    await asyncio.wait([receive, restart], return_when=asyncio.FIRST_COMPLETED)
    if not receive.done():
        # The restart is set. A message already on its way is handled first: it may be
        # intent-start, after which nothing is cancelled.
        await asyncio.wait([receive], timeout=_DRAIN_S)
    if receive.done():
        return _message(receive.result())
    # websockets: cancelling recv() loses no message.
    receive.cancel()
    await asyncio.gather(receive, return_exceptions=True)
    return None


def _message(raw: Any) -> dict[str, Any]:
    message = json.loads(raw)
    if not isinstance(message, dict):
        raise TypeError("message is not an object")
    return message


def _ms(data: dict[str, Any]) -> int:
    timestamp = data.get("timestamp")
    return int(timestamp) if isinstance(timestamp, int | float) else 0


def _record(run: _Run, delta: dict[str, Any]) -> None:
    """Tool calls and results from one chat log delta (conversation/chat_log.py)."""
    for call in delta.get("tool_calls") or []:
        if isinstance(call, dict) and isinstance(call.get("tool_name"), str):
            run.tools.append(ToolUse(call["tool_name"], call.get("tool_args"), external=call.get("external") is True))
    if delta.get("role") == "tool_result" and isinstance(delta.get("tool_name"), str):
        result = delta.get("result")
        failed = result.get("error") is True if isinstance(result, dict) else None
        # The result belongs to the newest call of that tool without one.
        for i in range(len(run.tools) - 1, -1, -1):
            tool = run.tools[i]
            if tool.name == delta["tool_name"] and tool.failed is None:
                run.tools[i] = ToolUse(tool.name, tool.args, failed, tool.external)
                break


def _turn(run: _Run, policy: ToolPolicy, reason: str) -> HomeTurn:
    """The run's outcome, from what it did rather than what it said."""
    tools = tuple(run.tools)

    def made(outcome: Outcome, speech: str = "", why: str = "", asks: bool = False) -> HomeTurn:
        return HomeTurn(run.turn, outcome, speech, run.heard, tools, run.speech_start, run.speech_end, why, asks)

    if run.output is None:
        why = reason or run.error or "no result"
        # Without intent-end, only a run that never reached its intent stage surely did nothing.
        return made(Outcome.UNCERTAIN if run.intent_started else Outcome.FAILED, why=why)
    response = run.output.get("response") if isinstance(run.output.get("response"), dict) else {}
    speech = str((((response.get("speech") or {}).get("plain") or {}).get("speech")) or "").strip()
    response_type = response.get("response_type")
    data = response.get("data") if isinstance(response.get("data"), dict) else {}
    targets = bool(data.get("success") or data.get("failed"))
    kinds = {policy.kind(tool) for tool in tools}
    if "non_home" in kinds:
        log.warning("home assistant turn %d used a non-home tool", run.turn)
    # Home Assistant continues the conversation whenever its reply ends in a question
    # (conversation/chat_log.py), "Done. Anything else?" included: the question is carried
    # beside what the turn did, never in place of it.
    asks = run.output.get("continue_conversation") is True and response_type != "error" and bool(speech)
    if "action" in kinds:
        return made(Outcome.ACTED, speech, asks=asks)
    if run.processed_locally and response_type != "error":
        if targets:
            return made(Outcome.ACTED if response_type != "query_answer" else Outcome.ANSWERED, speech, asks=asks)
        if response_type == "action_done":
            # A local action without targets: a sentence trigger's automation, or a timer.
            return made(Outcome.ACTED, speech, asks=asks)
    if asks:
        return made(Outcome.ASKED, speech, asks=True)
    if "read" in kinds:
        return made(Outcome.ANSWERED, speech)
    if response_type == "error" and not run.processed_locally:
        # The agent itself failed before calling any tool: nothing was done.
        return made(Outcome.FAILED, why=str(data.get("code") or "agent error"))
    return made(Outcome.ABSTAINED)
