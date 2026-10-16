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
from collections import deque
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import AbstractAsyncContextManager, asynccontextmanager
from dataclasses import dataclass
from typing import Any

import numpy as np
from openai import AsyncOpenAI
from openai.resources.live.live import AsyncLiveConnection
from openai.types.live.initial_item_param import InitialItemParam
from openai.types.live.session_config_param import SessionConfigParam

from .config import Live
from .dsp import mic_to_speaker_rate
from .home_assistant import HomeAssistantFailed, HomeReply
from .openclaw import ConsultFailed, HistoryUnavailable, Role, Turn
from .protocol import SPEAKER_RATE, Phase
from .routing import RouteDecision, RouteRequest, RoutingFailed
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

# Routed requests: what Live is told when nothing ran, and how a Home Assistant question reaches the user.
_NOT_ROUTED = "Nothing was done: the request could not be routed just now. Tell the user and ask them to try again."
_CLARIFY = "Nothing was done: it is unclear what to act on. Ask the user what they want done."
_HOME_UNCERTAIN = "Home Assistant gave no answer and may have acted anyway. Tell the user to check before asking again."
_STILL_SPEAKING = "Nothing was done yet: the user was still speaking. Let them finish, then delegate the whole request."
_HOME_ASKS = "Home Assistant asks: {question}\nAsk the user this, then delegate their answer, whatever it is."
# Waiting for the transcript to settle ends here; a longer stream is still speech in progress.
_SETTLE_MAX_S = 2.0
# Classifications of one request when more of it keeps arriving while it is classified.
_ROUTE_ATTEMPTS = 3

# Opens a Live connection; injected so tests can substitute OpenAI.
LiveConnector = Callable[[], AbstractAsyncContextManager[AsyncLiveConnection]]
# The agent's answer to a task; raises ConsultFailed.
Consult = Callable[[str], Awaitable[str]]
# The agent's recent conversation; raises HistoryUnavailable.
Recall = Callable[[], Awaitable[list[Turn]]]


@dataclass(frozen=True, slots=True)
class Routed:
    """Delegated requests classified, then answered by Home Assistant or by the consult."""

    # Picks the backend; raises RoutingFailed.
    route: Callable[[RouteRequest], Awaitable[RouteDecision]]
    # Home Assistant's reply to text, continuing a conversation ID; raises HomeAssistantFailed.
    converse: Callable[[str, str | None], Awaitable[HomeReply]]
    # How long a question Home Assistant asked stays answerable.
    pending_question_s: float
    # Quiet after the last user transcript fragment before a request counts as complete.
    settle_s: float


@dataclass(frozen=True, slots=True)
class _Pending:
    """A question Home Assistant asked at this speaker and waits on."""

    conversation_id: str
    question: str
    # time.monotonic() past which it is dropped
    expires: float


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
        routed: Routed | None = None,
    ) -> None:
        self._config = config
        self._area = area
        self._consult = consult
        # None: every delegation is a consult.
        self._routed = routed
        # This conversation's open Home Assistant question; it dies with the conversation.
        self._pending: _Pending | None = None
        # Live timeline start (ms) of each user transcript fragment heard, which the settling wait watches.
        self._user_starts: list[int] = []
        # Live timeline position (ms) of the newest delegation.
        self._delegation_offset: int | None = None
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
                    self._host.play(samples)
                case "session.input_transcript.delta":
                    self._host.mark_activity()
                    self._user_starts.append(event.start_ms)
                    self._hear("user", event.delta)
                case "session.output_transcript.delta":
                    self._hear("assistant", event.delta)
                case "session.delegation.created":
                    await self._host.set_phase(Phase.THINKING)
                    self._delegation_offset = event.offset_ms
                    self._delegate(event.delegation.id)
                case "session.closed":
                    log.info("live session closed: %s after %.1f s", event.reason, event.usage.seconds)
                    return
                case "error":
                    log.error("openai error: %s (%s)", event.error.message, event.error.code)
        self._flush_transcripts()

    def _hear(self, role: Role, text: str) -> None:
        if self._heard and self._heard[-1][0] != role:
            self._flush_transcripts()
        self._heard.append((role, text))

    # -- delegation ----------------------------------------------------------

    def _delegate(self, delegation_id: str) -> None:
        self._delegation = delegation_id
        # A running consult is a turn of the agent's own session, so it runs to its end.
        if self._consulting is None:
            self._consulting = asyncio.create_task(
                self._run_consults() if self._routed is None else self._run_routed(self._routed)
            )
        else:
            log.info("delegation %s waits for the running consult", delegation_id)

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

    async def _run_routed(self, routed: Routed) -> None:
        """Like _run_consults, but each request goes to the one backend its classification picks."""
        assert self._conn is not None and self._host is not None
        try:
            while True:
                delegation = self._delegation
                answer = await self._answer_routed(routed)
                for chunk in _chunks(answer):
                    await self._conn.session.commentary.append(content=chunk, delegation_id=self._delegation)
                unheard = self._heard[self._consulted :]
                if self._delegation == delegation or not any(role == "user" for role, _ in unheard):
                    break
        finally:
            if self._consulting is asyncio.current_task():
                self._consulting = None
            self._host.mark_activity()
        if not self.busy and not self._host.assistant_audible:
            await self._host.set_phase(Phase.LISTENING)

    async def _settled(self, settle_s: float) -> bool:
        """Whether the user's transcript went quiet for `settle_s`, within _SETTLE_MAX_S.

        Live delegates with no end-of-utterance marker, and the transcript can trail it.
        """
        deadline = time.monotonic() + _SETTLE_MAX_S
        while True:
            seen = len(self._user_starts)
            await asyncio.sleep(settle_s)
            if len(self._user_starts) == seen:
                return True
            if time.monotonic() >= deadline:
                return False

    async def _answer_routed(self, routed: Routed) -> str:
        """The answer to what the user said since the last request, from the backend it is routed to."""
        for _ in range(_ROUTE_ATTEMPTS):
            if not await self._settled(routed.settle_s):
                # Left unconsumed: the next delegation takes the whole request.
                return _STILL_SPEAKING
            offset = self._delegation_offset
            upto = len(self._heard)
            heard = self._heard[self._consulted : upto]
            text = " ".join(t.strip() for role, t in _turns(heard) if role == "user").strip()
            if not text:
                return "No transcript of the request arrived; ask the user to repeat it."
            # Everything said before the request, the voice asking a question included.
            first = next(i for i, (role, _) in enumerate(heard) if role == "user")
            context = tuple(_turns(self._heard[: self._consulted + first]))
            pending = self._pending
            if pending is not None and pending.expires <= time.monotonic():
                log.info("dropped an expired Home Assistant question")
                pending = self._pending = None
            fragments = len(self._user_starts)
            request = RouteRequest(text, context, self._area, pending.question if pending else None)
            try:
                decision = await routed.route(request)
            except Exception as e:  # noqa: BLE001 -- classifying acts on nothing, so any failure asks again
                # Class name only for a bug: its message could quote the request.
                log.warning("routing failed, nothing run: %s", e if isinstance(e, RoutingFailed) else type(e).__name__)
                self._pending = None
                self._consulted = upto
                return _NOT_ROUTED
            # The transcript trailed past the settling wait: speech from before the
            # delegation, so part of this request, arrived while it was classified.
            # Classify the whole of it instead of running a part.
            late = self._user_starts[fragments:]
            if offset is not None and any(start < offset for start in late):
                log.info("more of the request arrived while routing it; routing it again")
                continue
            # Taken whatever happens next: only a new question from Home Assistant opens another.
            self._pending = None
            # Consumed before anything runs: a backend that failed may still have
            # acted, so a later delegation must not run the request again.
            self._consulted = upto
            return await self._run_backend(routed, decision, text, heard, pending)
        return _STILL_SPEAKING

    async def _run_backend(
        self, routed: Routed, decision: RouteDecision, text: str, heard: list[Turn], pending: _Pending | None
    ) -> str:
        log.info(
            "route %s confidence=%s in %.0f ms%s",
            decision.route,
            decision.confidence,
            decision.elapsed_ms,
            " answering a Home Assistant question" if pending else "",
        )
        match decision.route:
            case "clarify":
                return _CLARIFY
            case "openclaw":
                try:
                    return await self._consult(self._task(heard))
                except ConsultFailed as e:
                    log.warning("consult failed: %s", e)
                    return f"The request failed: {e}"
            case "ha":
                try:
                    # A pending question continues even into an unrelated home request: the
                    # conversation agent sees the change of subject, and only its own context carries over.
                    reply = await routed.converse(text, pending.conversation_id if pending else None)
                except HomeAssistantFailed as e:
                    log.warning("home assistant failed: %s", e)
                    return _HOME_UNCERTAIN
                log.info("home assistant -> %s", reply.speech)
                if reply.continue_conversation and reply.conversation_id is not None:
                    self._pending = _Pending(
                        reply.conversation_id, reply.speech, time.monotonic() + routed.pending_question_s
                    )
                    return _HOME_ASKS.format(question=reply.speech)
                return reply.speech

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
            log.info("openai: %r", event)

    def _flush_transcripts(self) -> None:
        """Transcripts arrive as fragments with no end marker; log each side's run as a line."""
        for role, text in _turns(self._heard[self._logged :]):
            log.info("%s: %s", role, text.strip())
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
