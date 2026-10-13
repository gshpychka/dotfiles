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
from .session import Host, SessionRefused, located, placement

log = logging.getLogger(__name__)

# Base64 audio, dozens per second; the recordings hold the same audio.
_AUDIO_EVENTS = frozenset({"session.output_audio.delta"})
# An append carries at most 500 tokens, and every token spans at least one byte.
_APPEND_MAX_BYTES = 500
# Live takes this many initial messages at most.
_INPUT_MAX_ITEMS = 128
# Leads the initial messages, which are the agent's conversation before this one.
_HISTORY_LEAD = "Your text conversation with the user so far; the spoken conversation follows it."

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
    def __init__(self, config: Live, area: str, consult: Consult, recall: Recall, connect: LiveConnector) -> None:
        self._config = config
        self._area = area
        self._consult = consult
        self._recall = recall
        self._connect = connect
        self._to_openai_rate = mic_to_speaker_rate()
        self._conn: AsyncLiveConnection | None = None
        self._host: Host | None = None
        # Transcript fragments in delivery order.
        self._heard: list[Turn] = []
        self._logged = 0
        # Fragments before this index reached the agent in a consult it answered.
        self._consulted = 0
        self._consulting: asyncio.Task[None] | None = None

    @asynccontextmanager
    async def open(self, host: Host) -> AsyncIterator[None]:
        try:
            history = await self._recall()
        except HistoryUnavailable as e:
            log.warning("starting without the recent conversation: %s", e)
            history = []
        async with self._connect() as conn:
            self._conn = conn
            self._host = host
            await conn.session.start(session=self._session_config(history))
            async for event in conn:
                self._log_event(event)
                if event.type == "session.started":
                    break
                if event.type == "error":
                    raise SessionRefused(f"{event.error.message} ({event.error.code})")
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
        if history:
            config["input"] = _initial_items(history)
        return config

    # -- mic -----------------------------------------------------------------

    async def on_mic(self, samples: np.ndarray) -> None:
        if self._conn is None or len(samples) == 0:
            return
        upsampled = self._to_openai_rate(samples)
        if len(upsampled):
            await self._conn.session.input_audio.append(audio=base64.b64encode(upsampled.tobytes()).decode())

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
                    self._hear("user", event.delta)
                case "session.output_transcript.delta":
                    self._hear("assistant", event.delta)
                case "session.delegation.created":
                    await self._host.set_phase(Phase.THINKING)
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
        # The new task's transcript holds everything the superseded one did.
        if self._consulting is not None:
            log.info("delegation %s supersedes the running consult", delegation_id)
            self._consulting.cancel()
        self._consulting = asyncio.create_task(self._run_consult(delegation_id))

    async def _run_consult(self, delegation_id: str) -> None:
        assert self._conn is not None and self._host is not None
        upto = len(self._heard)
        heard = self._heard[self._consulted : upto]
        try:
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
                await self._conn.session.commentary.append(content=chunk, delegation_id=delegation_id)
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
            log.info("openai: %r", event)

    def _flush_transcripts(self) -> None:
        """Transcripts arrive as fragments with no end marker; log each side's run as a line."""
        for role, text in _turns(self._heard[self._logged :]):
            log.info("%s: %s", role, text.strip())
        self._logged = len(self._heard)


def _initial_items(history: list[Turn]) -> list[InitialItemParam]:
    """The newest of `history` as Live's initial messages, led by what they are."""
    items: list[InitialItemParam] = [
        {"type": "message", "role": "developer", "content": [{"type": "input_text", "text": _HISTORY_LEAD}]}
    ]
    for role, text in history[-(_INPUT_MAX_ITEMS - 1) :]:
        if role == "user":
            items.append({"type": "message", "role": "user", "content": [{"type": "input_text", "text": text}]})
        else:
            items.append({"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": text}]})
    return items


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
