"""One conversation: a device WebSocket bridged to one OpenAI model session.

Audio path, device mic to OpenAI:
    MIC frames -> Aligner (pairs each 10 ms with what the speaker played)
    -> AEC3 -> the model session, which decides what reaches OpenAI

Audio path, OpenAI to device speaker:
    model audio -> pending queue -> paced to the device so at most
    PLAYBACK_LEAD is buffered there. Keeping the device buffer short makes a
    flush instant and keeps the "what was heard" position accurate.
"""

from __future__ import annotations

import asyncio
import enum
import logging
import time
from collections import deque
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any, Protocol

import numpy as np
from websockets.exceptions import ConnectionClosed

from ._aec import EchoCanceller
from .alignment import AlignedBlock, Aligner
from .config import Config
from .dsp import speaker_to_mic_rate
from .protocol import (
    SPEAKER_RATE,
    ControlType,
    MicFrame,
    Phase,
    PlayedReport,
    ProtocolError,
    encode_audio,
    encode_control,
    parse_binary,
    parse_control,
)
from .recorder import NullRecorder, Recorder
from .session import Heard, ModelSession, SessionRefused

log = logging.getLogger(__name__)

PLAYBACK_LEAD = SPEAKER_RATE * 300 // 1000
_SEND_CHUNK = SPEAKER_RATE * 40 // 1000
_PUMP_INTERVAL_S = 0.01
# No PLAYED report for this long while audio is in flight means the device lost
# its playback; stop waiting for it instead of hanging the conversation.
_PLAYED_STALL_S = 2.0
# Output peaks at or below this are silence: GPT-Live streams ±1 LSB between utterances.
_SILENCE_PEAK = 32
# Silence shorter than this inside a reply keeps the assistant audible.
_SOUND_HANGOVER = SPEAKER_RATE * 600 // 1000


class EndReason(enum.StrEnum):
    DEVICE_STOP = "device stop"
    DEVICE_GONE = "device disconnected"
    IDLE = "idle"
    MAX_DURATION = "max duration"
    OPENAI_GONE = "openai disconnected"


@dataclass
class _AssistantItem:
    item_id: str
    # Position in the sent stream (SPEAKER_RATE samples) of this item's first sample.
    stream_start: int
    samples: int = 0


class DeviceSocket(Protocol):
    """The subset of websockets' ServerConnection a conversation uses."""

    def __aiter__(self) -> AsyncIterator[str | bytes]: ...
    async def send(self, message: str | bytes) -> None: ...
    async def close(self) -> None: ...


class Conversation:
    def __init__(
        self, config: Config, name: str, device: DeviceSocket, session: ModelSession, aec: EchoCanceller
    ) -> None:
        self._config = config
        self._device = device
        self._session = session
        self._aligner = Aligner()
        # One per device, reused across its conversations: AEC3 suppresses
        # conservatively for its first seconds, and the room echo path it has
        # learned stays valid between conversations.
        self._aec = aec
        self._to_mic_rate = speaker_to_mic_rate()
        self._recorder: Recorder | NullRecorder = (
            Recorder(config.recordings_dir, name) if config.recordings_dir else NullRecorder()
        )

        self._pending: deque[np.ndarray] = deque()  # SPEAKER_RATE audio not yet sent
        self._pending_samples = 0
        self._sent_samples = 0  # SPEAKER_RATE samples sent this conversation
        self._item: _AssistantItem | None = None
        # Stream position just past the last queued audio that carries sound.
        self._sound_end: int | None = None
        self._phase: Phase | None = None
        self._mic_index = 0
        self._last_activity = time.monotonic()
        self._last_played = time.monotonic()
        self._ended = asyncio.Event()
        self.end_reason: EndReason | None = None

    # -- lifecycle -----------------------------------------------------------

    async def run(self) -> EndReason:
        started = time.monotonic()
        try:
            async with self._session.open(self):
                await self.set_phase(Phase.LISTENING)
                tasks = [
                    asyncio.create_task(self._device_loop(), name="device"),
                    asyncio.create_task(self._receive(), name="openai"),
                    asyncio.create_task(self._pump_loop(), name="pump"),
                    asyncio.create_task(self._watchdog(started), name="watchdog"),
                ]
                ended = asyncio.create_task(self._ended.wait())
                await asyncio.wait([*tasks, ended], return_when=asyncio.FIRST_COMPLETED)
                for task in tasks:
                    task.cancel()
                results = await asyncio.gather(*tasks, return_exceptions=True)
                for task, result in zip(tasks, results, strict=True):
                    if isinstance(result, BaseException) and not isinstance(result, asyncio.CancelledError):
                        log.error("conversation task %s failed", task.get_name(), exc_info=result)
                ended.cancel()
        except SessionRefused as e:
            log.error("openai refused the session: %s", e)
        finally:
            self._recorder.close()
            try:
                await self._device.send(encode_control(ControlType.END))
                await self._device.close()
            except ConnectionClosed:
                pass
        return self.end_reason or EndReason.OPENAI_GONE

    def _end(self, reason: EndReason) -> None:
        if self.end_reason is None:
            self.end_reason = reason
            log.info("conversation ending: %s", reason)
        self._ended.set()

    async def _receive(self) -> None:
        await self._session.receive()
        self._end(EndReason.OPENAI_GONE)

    # -- Host ----------------------------------------------------------------

    @property
    def assistant_audible(self) -> bool:
        queued = self._pending_samples > 0 or self._aligner.in_flight_speaker_samples > 0
        if not queued or self._sound_end is None:
            return False
        return self._aligner.played_speaker_samples < self._sound_end + _SOUND_HANGOVER

    def play(self, samples: np.ndarray, item_id: str | None) -> None:
        if item_id is not None:
            if self._item is None or self._item.item_id != item_id:
                self._item = _AssistantItem(item_id, stream_start=self._sent_samples + self._pending_samples)
            self._item.samples += len(samples)
        if len(samples) and (samples.max() > _SILENCE_PEAK or samples.min() < -_SILENCE_PEAK):
            self._sound_end = self._sent_samples + self._pending_samples + len(samples)
        self._pending.append(samples)
        self._pending_samples += len(samples)

    async def flush(self) -> Heard | None:
        await self._device.send(encode_control(ControlType.FLUSH))
        self._pending.clear()
        self._pending_samples = 0
        played = self._aligner.played_speaker_samples
        self._aligner.begin_flush()
        # The device drops unplayed audio, so the stream resumes from what was played.
        self._sent_samples = played
        self._to_mic_rate = speaker_to_mic_rate()
        self._sound_end = None
        item, self._item = self._item, None
        if item is None:
            return None
        heard = min(max(0, played - item.stream_start), item.samples)
        return Heard(item.item_id, heard * 1000 // SPEAKER_RATE)

    async def set_phase(self, phase: Phase) -> None:
        if phase != self._phase:
            log.info("phase: %s", phase.value)
            self._phase = phase
            await self._device.send(encode_control(ControlType.PHASE, phase=phase.value))

    def mark_activity(self) -> None:
        self._last_activity = time.monotonic()

    def record_event(self, kind: str, **fields: Any) -> None:
        self._recorder.event(self._mic_index, kind, aec=self._aec.stats(), **fields)

    # -- device side ---------------------------------------------------------

    async def _device_loop(self) -> None:
        try:
            async for message in self._device:
                if isinstance(message, str):
                    kind, fields = parse_control(message)
                    log.info("device: %s %s", kind, fields)
                    if kind == ControlType.STOP:
                        self._end(EndReason.DEVICE_STOP)
                        return
                    if kind == ControlType.FLUSHED:
                        self._aligner.end_flush()
                        continue
                    log.warning("unexpected control from device: %s", kind)
                    continue
                try:
                    frame = parse_binary(message)
                except ProtocolError as e:
                    log.warning("dropping device frame: %s", e)
                    continue
                match frame:
                    case MicFrame():
                        self._aligner.add_mic(frame)
                        for block in self._aligner.blocks():
                            await self._process_block(block)
                    case PlayedReport():
                        self._aligner.add_played(frame)
                        self._last_played = time.monotonic()
        except ConnectionClosed:
            pass
        self._end(EndReason.DEVICE_GONE)

    async def _process_block(self, block: AlignedBlock) -> None:
        self._aec.process_reverse(block.reference)
        cleaned = np.frombuffer(self._aec.process_capture(block.mic), dtype=np.int16)
        self._recorder.block(block.mic, block.reference, cleaned)
        self._mic_index = block.mic_index
        if self.assistant_audible:
            self.mark_activity()
        await self._session.on_mic(cleaned)

    # -- playback ------------------------------------------------------------

    async def _pump_loop(self) -> None:
        while True:
            await asyncio.sleep(_PUMP_INTERVAL_S)
            in_flight = self._aligner.in_flight_speaker_samples
            if in_flight and time.monotonic() - self._last_played > _PLAYED_STALL_S:
                log.warning("device stopped reporting playback with %d samples in flight", in_flight)
                self._aligner.abandon_in_flight()
                in_flight = 0
            while self._pending and in_flight < PLAYBACK_LEAD and not self._aligner.flushing:
                chunk = self._take_pending(_SEND_CHUNK)
                self._aligner.add_sent(len(chunk), self._to_mic_rate(chunk))
                self._sent_samples += len(chunk)
                in_flight += len(chunk)
                if in_flight == len(chunk):
                    # Playback starting from idle: the stall clock starts now.
                    self._last_played = time.monotonic()
                await self._device.send(encode_audio(chunk.astype("<i2").tobytes()))
            if self.assistant_audible:
                await self.set_phase(Phase.REPLYING)
            elif self._phase == Phase.REPLYING:
                # Finished playing without interruption.
                self._session.on_playback_finished()
                self.mark_activity()
                await self.set_phase(Phase.THINKING if self._session.busy else Phase.LISTENING)

    def _take_pending(self, n: int) -> np.ndarray:
        parts = []
        while self._pending and n > 0:
            head = self._pending[0]
            if len(head) <= n:
                parts.append(self._pending.popleft())
                n -= len(head)
            else:
                parts.append(head[:n])
                self._pending[0] = head[n:]
                n = 0
        chunk = np.concatenate(parts)
        self._pending_samples -= len(chunk)
        return chunk

    # -- limits --------------------------------------------------------------

    async def _watchdog(self, started: float) -> None:
        while True:
            await asyncio.sleep(0.5)
            now = time.monotonic()
            if now - started > self._config.max_conversation_s:
                self._end(EndReason.MAX_DURATION)
                return
            busy = self.assistant_audible or self._session.busy
            if not busy and now - self._last_activity > self._config.idle_timeout_s:
                self._end(EndReason.IDLE)
                return
