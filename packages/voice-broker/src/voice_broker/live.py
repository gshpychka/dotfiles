"""The full-duplex OpenAI Live backend.

GPT-Live listens while it speaks and decides for itself when to talk, yield or
keep going, so the echo-cancelled mic streams to it continuously and playback
only ever ends when it stops sending audio. Work it delegates goes to an agent
as a consult on the conversation's transcript, and GPT-Live speaks the answer.
"""

from __future__ import annotations

import asyncio
import base64
import logging
import time
import uuid
from collections import deque
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import AbstractAsyncContextManager, asynccontextmanager
from typing import Any

import numpy as np
from openai import AsyncOpenAI
from openai.resources.live.live import AsyncLiveConnection
from openai.types.live.initial_item_param import InitialItemParam
from openai.types.live.session_config_param import SessionConfigParam

from .config import Live
from .dsp import mic_to_speaker_rate
from .openclaw import ConsultFailed, HistoryUnavailable, Role, Turn
from .protocol import SPEAKER_RATE, Phase
from .routing import RouteRequest
from .session import Host, SessionRefused, located, placement

log = logging.getLogger(__name__)

# Base64 audio, dozens per second; the recordings hold the same audio.
_AUDIO_EVENTS = frozenset({"session.output_audio.delta"})
# An append carries at most 500 tokens, and every token spans at least one byte.
_APPEND_MAX_BYTES = 500
# Live takes this many initial messages at most.
_INPUT_MAX_ITEMS = 128
# Mic audio held for a session still starting; the device gives a startup 10 s.
_BACKLOG_MAX_SAMPLES = SPEAKER_RATE * 15
# Leads the initial messages, which are the agent's conversation before this one.
_HISTORY_LEAD = "Your text conversation with the user so far; the spoken conversation follows it."
# Ends the initial messages of a call: the backend is what the instructions call the agent.
_OPENING_LEAD = (
    "You opened this conversation for the backend, which has something to tell the user. Begin by telling them: "
    "{opening}\nDelegate the user's response to the backend, whatever it is."
)

# Opens a Live connection; injected so tests can substitute OpenAI.
LiveConnector = Callable[[], AbstractAsyncContextManager[AsyncLiveConnection]]
# The agent's answer to a task; raises ConsultFailed.
Consult = Callable[[str], Awaitable[str]]
# The agent's recent conversation; raises HistoryUnavailable.
Recall = Callable[[], Awaitable[list[Turn]]]


def live_connector(client: AsyncOpenAI) -> LiveConnector:
    # A dropped primary WebSocket ends the conversation; the SDK's reconnect
    # would resume mid-sentence with no audio in between.
    return lambda: client.live.connect(max_retries=0)


class LiveSession:
    def __init__(
        self,
        config: Live,
        area: str,
        consult: Consult,
        recall: Recall,
        connect: LiveConnector,
        opening: str | None = None,
        *,
        routed: Callable[[RouteRequest], Awaitable[str]] | None = None,
        device: str = "",
        settle_s: float = 0.35,
        remember: Callable[[RouteRequest, str], Awaitable[None]] | None = None,
        persist: Callable[[RouteRequest, str], None] | None = None,
    ) -> None:
        self._config = config
        self._routed = routed
        self._remember = remember
        self._persist = persist
        self._device = device
        self._settle_s = settle_s
        self._conversation_id = uuid.uuid4().hex
        self._history: list[Turn] = []
        self._backend_results: list[Turn] = []
        self._input_revision = 0
        self._last_user_change = 0.0
        self._last_user_end: float | None = None
        self._delegation_offset: float | None = None
        self._seen_delegations: set[str] = set()
        self._request_revision = -1
        self._reply_started: float | None = None
        self._area = area
        self._consult = consult
        self._recall = recall
        self._connect = connect
        # What the voice says first, in a conversation the agent opened.
        self._opening = opening
        self._to_openai_rate = mic_to_speaker_rate()
        self._conn: AsyncLiveConnection | None = None
        self._host: Host | None = None
        # Mic audio heard before the session is open, at SPEAKER_RATE, in order.
        self._backlog: deque[np.ndarray] = deque()
        self._backlog_samples = 0
        # Transcript fragments in delivery order.
        self._heard: list[Turn] = []
        self._logged = 0
        # Fragments before this index reached the agent in a consult it answered.
        self._consulted = 0
        self._consulting: asyncio.Task[None] | None = None
        # The newest delegation, which answers go to: a newer one supersedes the old on the model's side.
        self._delegation: str | None = None

    @asynccontextmanager
    async def open(self, host: Host) -> AsyncIterator[None]:
        try:
            history = await self._recall()
        except HistoryUnavailable as e:
            log.warning("starting without the recent conversation: %s", e)
            history = []
        self._history = history
        async with self._connect() as conn:
            self._host = host
            await conn.session.start(session=self._session_config(history))
            async for event in conn:
                self._log_event(event)
                if event.type == "session.started":
                    break
                if event.type == "error":
                    raise SessionRefused(f"{event.error.message} ({event.error.code})")
            # What the mic sent so far goes first; a block arriving meanwhile joins the backlog.
            while self._backlog:
                samples = self._backlog.popleft()
                self._backlog_samples -= len(samples)
                await conn.session.input_audio.append(audio=_audio(samples))
            self._conn = conn
            try:
                yield
            finally:
                if self._consulting is not None:
                    self._consulting.cancel()
                    await asyncio.gather(self._consulting, return_exceptions=True)
                self._conn = None

    @property
    def busy(self) -> bool:
        return self._consulting is not None

    def on_playback_finished(self) -> None:
        self._flush_transcripts()

    def _session_config(self, history: list[Turn]) -> SessionConfigParam:
        config: SessionConfigParam = {
            "model": self._config.model,
            "instructions": located(self._config.instructions, self._area),
            "audio": {
                "format": {"type": "audio/pcm", "rate": SPEAKER_RATE},
                "output": {"voice": self._config.voice},
            },
            "delegation": {"type": "client"},
        }
        if items := _initial_items(history, self._opening):
            config["input"] = items
        return config

    # -- mic -----------------------------------------------------------------

    async def on_mic(self, samples: np.ndarray) -> None:
        if len(samples) == 0:
            return
        upsampled = self._to_openai_rate(samples)
        if len(upsampled) == 0:
            return
        if self._conn is None:
            self._hold(upsampled)
            return
        await self._conn.session.input_audio.append(audio=_audio(upsampled))

    def _hold(self, samples: np.ndarray) -> None:
        self._backlog.append(samples)
        self._backlog_samples += len(samples)
        while self._backlog_samples > _BACKLOG_MAX_SAMPLES:
            self._backlog_samples -= len(self._backlog.popleft())

    # -- OpenAI side ---------------------------------------------------------

    async def receive(self) -> None:
        assert self._conn is not None and self._host is not None
        async for event in self._conn:
            self._log_event(event)
            match event.type:
                case "session.output_audio.delta":
                    samples = np.frombuffer(base64.b64decode(event.delta), dtype="<i2").astype(np.int16)
                    if (
                        self._reply_started is not None
                        and len(samples)
                        and np.max(np.abs(samples.astype(np.int32))) > 32
                    ):
                        log.info("latency first_reply_ms=%.1f", (time.monotonic() - self._reply_started) * 1000)
                        self._reply_started = None
                    self._host.play(samples)
                case "session.input_transcript.delta":
                    self._host.mark_activity()
                    self._hear("user", event.delta)
                    self._last_user_end = getattr(event, "end_ms", None)
                case "session.output_transcript.delta":
                    self._hear("assistant", event.delta)
                case "session.delegation.created":
                    await self._host.set_phase(Phase.THINKING)
                    if event.delegation.id not in self._seen_delegations:
                        self._delegation_offset = getattr(event, "offset_ms", None)
                        self._delegate(event.delegation.id)
                case "session.closed":
                    log.info("live session closed: %s after %.1f s", event.reason, event.usage.seconds)
                    return
                case "error":
                    log.error("openai error code=%s", event.error.code)
        self._flush_transcripts()

    def _hear(self, role: Role, text: str) -> None:
        if role == "user":
            self._input_revision += 1
            self._last_user_change = time.monotonic()
        if self._heard and self._heard[-1][0] != role:
            self._flush_transcripts()
        self._heard.append((role, text))

    # -- delegation ----------------------------------------------------------

    def _delegate(self, delegation_id: str) -> None:
        if delegation_id in self._seen_delegations:
            return
        self._seen_delegations.add(delegation_id)
        self._delegation = delegation_id
        self._reply_started = time.monotonic()
        # A running consult is a turn of the agent's own session, so it runs to its end.
        if self._consulting is None:
            self._consulting = asyncio.create_task(self._run_routed() if self._routed else self._run_consults())
        else:
            log.info("delegation %s waits for the running consult", delegation_id)

    def request_is_current(self, request: RouteRequest) -> bool:
        return self._request_revision == self._input_revision

    async def _settled(self) -> bool:
        # Live has no final transcript event. A delegation is the trigger, not
        # a completed utterance. Wait for late fragments; a bound prevents a
        # continuous speaker or missing transcript from holding execution open.
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            revision = self._input_revision
            await asyncio.sleep(self._settle_s)
            if revision == self._input_revision:
                return True
        return False

    async def _run_routed(self) -> None:
        assert self._conn is not None and self._host is not None and self._routed is not None
        try:
            while True:
                request = None
                stable = await self._settled()
                delegation = self._delegation
                upto = len(self._heard)
                heard = self._heard[self._consulted : upto]
                text = "".join(t for role, t in heard if role == "user").strip()
                correlated = (
                    self._last_user_end is not None
                    and self._delegation_offset is not None
                    and self._last_user_end <= self._delegation_offset
                )
                # Missing timing, continuation after the delegation, and a
                # visibly unfinished sentence cannot authorize execution.
                if not stable or not correlated or not text or text[-1] not in ".!?…":
                    answer = "The request is not complete yet. Please repeat the full request; no action was attempted."
                    self._consulted = upto
                else:
                    request = RouteRequest(
                        text,
                        tuple(self._history + _turns(self._heard[: self._consulted]) + self._backend_results),
                        self._area,
                        self._device,
                        self._conversation_id,
                    )
                    self._request_revision = self._input_revision
                    # Consume BEFORE execution: failure/timeout might mean an
                    # action happened. A new delegation must not replay it.
                    self._consulted = upto
                    try:
                        if self._persist:
                            self._persist(
                                request, "Execution started; outcome is unknown. Do not repeat automatically."
                            )
                        answer = await self._routed(request)
                    except OSError:
                        answer = "History storage is unavailable; no action was attempted."
                    except ConsultFailed:
                        answer = "The backend result is uncertain. Check the home before repeating; no other backend was run."
                if request is not None:
                    if self._persist:
                        try:
                            self._persist(request, answer)
                        except OSError:
                            log.error("backend result persistence failed; uncertain execution record retained")
                    self._backend_results.append(("assistant", "Already handled backend result: " + answer))
                for chunk in _chunks(answer):
                    await self._conn.session.commentary.append(content=chunk, delegation_id=self._delegation)
                if request is not None and self._remember is not None:
                    try:
                        await self._remember(request, answer)
                    except OSError:
                        log.error("voice history persistence failed; answer already delivered")
                if self._delegation == delegation:
                    break
                if not any(role == "user" for role, _ in self._heard[self._consulted :]):
                    break
        finally:
            self._consulting = None
            self._host.mark_activity()
            if not self._host.assistant_audible:
                await self._host.set_phase(Phase.LISTENING)

    async def _run_consults(self) -> None:
        """Consults until everything heard is answered at the newest delegation."""
        assert self._conn is not None and self._host is not None
        try:
            while True:
                delegation = self._delegation
                upto = len(self._heard)
                heard = self._heard[self._consulted : upto]
                if any(role == "user" for role, _ in heard):
                    try:
                        answer = await self._consult(self._task(heard))
                        self._consulted = upto
                    except ConsultFailed as e:
                        log.warning("consult failed: %s", e)
                        answer = f"The request failed: {e}"
                else:
                    answer = "No transcript of the request arrived; ask the user to repeat it."
                for chunk in _chunks(answer):
                    await self._conn.session.commentary.append(content=chunk, delegation_id=self._delegation)
                # A delegation created meanwhile has its answer, unless more was said since.
                unheard = self._heard[self._consulted :]
                if self._delegation == delegation or not any(role == "user" for role, _ in unheard):
                    break
        finally:
            if self._consulting is asyncio.current_task():
                self._consulting = None
            self._host.mark_activity()
        if not self.busy and not self._host.assistant_audible:
            await self._host.set_phase(Phase.LISTENING)

    def _task(self, heard: list[Turn]) -> str:
        said = "\n".join(f"{role}: {text.strip()}" for role, text in _turns(heard))
        return (
            f"{placement(self._area)}\n"
            "The conversation at this speaker since your last answer to it, from speech"
            f" recognition, which can mishear:\n{said}\n"
        )

    # -- logging -------------------------------------------------------------

    def _log_event(self, event: Any) -> None:
        if event.type not in _AUDIO_EVENTS:
            # Transcript, tool output and error details can contain private household content.
            log.debug("openai event: %s", event.type)

    def _flush_transcripts(self) -> None:
        """Transcripts arrive as fragments with no end marker; log each side's run as a line."""
        for role, text in _turns(self._heard[self._logged :]):
            log.debug("transcript role=%s chars=%d", role, len(text))
        self._logged = len(self._heard)


def _initial_items(history: list[Turn], opening: str | None) -> list[InitialItemParam]:
    """Live's initial messages: the newest of `history`, led by what it is, then the opening of a call."""
    items: list[InitialItemParam] = []
    if history:
        items.append(_developer(_HISTORY_LEAD))
        room = _INPUT_MAX_ITEMS - 1 - (1 if opening else 0)
        for role, text in history[-room:]:
            if role == "user":
                items.append({"type": "message", "role": "user", "content": [{"type": "input_text", "text": text}]})
            else:
                items.append(
                    {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": text}]}
                )
    if opening:
        items.append(_developer(_OPENING_LEAD.format(opening=opening)))
    return items


def _developer(text: str) -> InitialItemParam:
    return {"type": "message", "role": "developer", "content": [{"type": "input_text", "text": text}]}


def _audio(samples: np.ndarray) -> str:
    """SPEAKER_RATE samples as Live's base64 PCM."""
    return base64.b64encode(samples.tobytes()).decode()


def _turns(fragments: list[Turn]) -> list[Turn]:
    """Consecutive fragments from one side, joined."""
    turns: list[Turn] = []
    for role, text in fragments:
        if turns and turns[-1][0] == role:
            turns[-1] = (role, turns[-1][1] + text)
        else:
            turns.append((role, text))
    return turns


def _chunks(text: str) -> list[str]:
    """`text` split between words into appends of at most _APPEND_MAX_BYTES."""
    chunks: list[str] = []
    for word in text.split():
        if chunks and len(f"{chunks[-1]} {word}".encode()) <= _APPEND_MAX_BYTES:
            chunks[-1] = f"{chunks[-1]} {word}"
        else:
            chunks.append(word.encode()[:_APPEND_MAX_BYTES].decode(errors="ignore"))
    return chunks
