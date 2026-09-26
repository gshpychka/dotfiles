"""One conversation: a device WebSocket bridged to one OpenAI Realtime session.

Audio path, device mic to OpenAI:
    MIC frames -> Aligner (pairs each 10 ms with what the speaker played)
    -> AEC3 -> while the assistant is audible: barge-in detector only
               otherwise: resampled to 24 kHz and streamed to OpenAI

While the assistant is audible, mic audio is *not* sent to OpenAI: whatever
echo survives cancellation would otherwise be taken as the user speaking. The
broker makes the interruption call itself (BargeInDetector), then stops
playback on the device, cancels the response, truncates the assistant's item
to what was actually heard, and replays the preroll so OpenAI hears the
interruption from its start.

Audio path, OpenAI to device speaker:
    response.output_audio.delta -> pending queue -> paced to the device so at
    most PLAYBACK_LEAD is buffered there. Keeping the device buffer short makes
    a flush instant and keeps the "what was heard" position accurate.
"""

from __future__ import annotations

import asyncio
import base64
import enum
import logging
import time
from collections import deque
from collections.abc import AsyncIterator, Callable
from contextlib import AbstractAsyncContextManager
from dataclasses import dataclass, field
from typing import Protocol

import numpy as np
from openai import AsyncOpenAI
from openai.resources.realtime.realtime import AsyncRealtimeConnection
from websockets.exceptions import ConnectionClosed

from ._aec import EchoCanceller
from .alignment import Aligner, AlignedBlock
from .bargein import BargeInDetector
from .config import Config
from .dsp import SileroVad, mic_to_speaker_rate, speaker_to_mic_rate
from .mcp_hub import McpHub
from .protocol import (
    MIC_RATE,
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

log = logging.getLogger(__name__)

PLAYBACK_LEAD = SPEAKER_RATE * 300 // 1000
_SEND_CHUNK = SPEAKER_RATE * 40 // 1000
_PUMP_INTERVAL_S = 0.01
# No PLAYED report for this long while audio is in flight means the device lost
# its playback; stop waiting for it instead of hanging the conversation.
_PLAYED_STALL_S = 2.0


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


@dataclass
class _Turn:
    response_id: str | None = None
    tool_calls: list[tuple[str, str, str]] = field(default_factory=list)  # call_id, name, arguments


class DeviceSocket(Protocol):
    """The subset of websockets' ServerConnection a conversation uses."""

    def __aiter__(self) -> AsyncIterator[str | bytes]: ...
    async def send(self, message: str | bytes) -> None: ...
    async def close(self) -> None: ...


# Opens a Realtime connection; injected so tests can substitute OpenAI.
RealtimeConnector = Callable[[], AbstractAsyncContextManager[AsyncRealtimeConnection]]


def openai_connector(client: AsyncOpenAI, model: str) -> RealtimeConnector:
    return lambda: client.realtime.connect(model=model)


class Conversation:
    def __init__(
        self,
        config: Config,
        hub: McpHub,
        device: DeviceSocket,
        connect: RealtimeConnector,
        aec: EchoCanceller,
    ) -> None:
        self._config = config
        self._hub = hub
        self._device = device
        self._connect = connect
        self._aligner = Aligner()
        # Owned by the broker and reused across conversations: AEC3 suppresses
        # conservatively for its first seconds, and the room echo path it has
        # learned stays valid between conversations.
        self._aec = aec
        self._barge_in = BargeInDetector(config.barge_in, SileroVad(config.vad_model))
        self._to_openai_rate = mic_to_speaker_rate()
        self._to_mic_rate = speaker_to_mic_rate()
        self._recorder: Recorder | NullRecorder = (
            Recorder(config.recordings_dir) if config.recordings_dir else NullRecorder()
        )

        self._rt: AsyncRealtimeConnection | None = None
        self._pending: deque[np.ndarray] = deque()  # SPEAKER_RATE audio not yet sent
        self._pending_samples = 0
        self._sent_samples = 0  # SPEAKER_RATE samples sent this conversation
        self._item: _AssistantItem | None = None
        self._silenced_items: set[str] = set()
        self._turn = _Turn()
        self._phase: Phase | None = None
        self._last_activity = time.monotonic()
        self._last_played = time.monotonic()
        self._tools_running = 0
        self._interrupted_since_tools = False
        self._ended = asyncio.Event()
        self.end_reason: EndReason | None = None

    # -- lifecycle -----------------------------------------------------------

    async def run(self) -> EndReason:
        started = time.monotonic()
        try:
            async with self._connect() as rt:
                self._rt = rt
                await rt.session.update(session=self._session_config())
                await self._set_phase(Phase.LISTENING)
                tasks = [
                    asyncio.create_task(self._device_loop(), name="device"),
                    asyncio.create_task(self._openai_loop(), name="openai"),
                    asyncio.create_task(self._pump_loop(), name="pump"),
                    asyncio.create_task(self._watchdog(started), name="watchdog"),
                ]
                ended = asyncio.create_task(self._ended.wait())
                done, _ = await asyncio.wait([*tasks, ended], return_when=asyncio.FIRST_COMPLETED)
                for task in tasks:
                    task.cancel()
                results = await asyncio.gather(*tasks, return_exceptions=True)
                for task, result in zip(tasks, results, strict=True):
                    if isinstance(result, BaseException) and not isinstance(result, asyncio.CancelledError):
                        log.error("conversation task %s failed", task.get_name(), exc_info=result)
                ended.cancel()
        finally:
            self._rt = None
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

    def _session_config(self) -> dict[str, object]:
        audio_input: dict[str, object] = {
            "format": {"type": "audio/pcm", "rate": SPEAKER_RATE},
            "noise_reduction": {"type": "far_field"},
            # The broker handles interruptions itself; see the module docstring.
            "turn_detection": {"type": "semantic_vad", "create_response": True, "interrupt_response": False},
        }
        if self._config.transcription_model:
            audio_input["transcription"] = {"model": self._config.transcription_model}
        return {
            "type": "realtime",
            "model": self._config.model,
            "instructions": self._config.instructions,
            "output_modalities": ["audio"],
            "audio": {
                "input": audio_input,
                "output": {"format": {"type": "audio/pcm", "rate": SPEAKER_RATE}, "voice": self._config.voice},
            },
            "tools": self._hub.realtime_tools(),
            "tool_choice": "auto",
        }

    async def _set_phase(self, phase: Phase) -> None:
        if phase != self._phase:
            self._phase = phase
            await self._device.send(encode_control(ControlType.PHASE, phase=phase.value))

    @property
    def _assistant_audible(self) -> bool:
        return self._pending_samples > 0 or self._aligner.in_flight_speaker_samples > 0

    # -- device side ---------------------------------------------------------

    async def _device_loop(self) -> None:
        try:
            async for message in self._device:
                if isinstance(message, str):
                    kind, fields = parse_control(message)
                    if kind == ControlType.START:
                        log.info("woken by %s", fields.get("wake_word"))
                        continue
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

        if self._assistant_audible:
            self._last_activity = time.monotonic()
            trigger = self._barge_in.feed(cleaned)
            if trigger is not None:
                self._recorder.event(
                    block.mic_index,
                    "barge_in",
                    speech_ms=trigger.speech_ms,
                    level_dbfs=round(trigger.level_dbfs, 1),
                    probability=round(trigger.probability, 3),
                    aec=self._aec.stats(),
                )
                await self._interrupt()
            return
        await self._send_to_openai(cleaned)

    async def _send_to_openai(self, samples: np.ndarray) -> None:
        if self._rt is None or len(samples) == 0:
            return
        upsampled = self._to_openai_rate(samples)
        if len(upsampled):
            await self._rt.input_audio_buffer.append(audio=base64.b64encode(upsampled.tobytes()).decode())

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
            if self._assistant_audible:
                await self._set_phase(Phase.REPLYING)
            elif self._phase == Phase.REPLYING:
                # Finished playing without interruption.
                self._barge_in.reset()
                self._last_activity = time.monotonic()
                await self._set_phase(Phase.THINKING if self._turn.response_id or self._tools_running else Phase.LISTENING)

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

    async def _interrupt(self) -> None:
        """The user talked over the assistant."""
        assert self._rt is not None
        await self._device.send(encode_control(ControlType.FLUSH))
        self._pending.clear()
        self._pending_samples = 0
        played = self._aligner.played_speaker_samples
        self._aligner.begin_flush()
        # The device drops unplayed audio, so the stream resumes from what was played.
        self._sent_samples = played
        self._to_mic_rate = speaker_to_mic_rate()
        self._interrupted_since_tools = True

        if self._turn.response_id is not None:
            await self._rt.response.cancel()
        if self._item is not None:
            # Deltas already in flight from OpenAI for this item must not play.
            self._silenced_items.add(self._item.item_id)
            heard = min(max(0, played - self._item.stream_start), self._item.samples)
            await self._rt.conversation.item.truncate(
                item_id=self._item.item_id, content_index=0, audio_end_ms=heard * 1000 // SPEAKER_RATE
            )
            self._item = None

        preroll = self._barge_in.preroll()
        self._barge_in.reset()
        await self._set_phase(Phase.LISTENING)
        await self._send_to_openai(preroll)

    # -- OpenAI side ---------------------------------------------------------

    async def _openai_loop(self) -> None:
        assert self._rt is not None
        async for event in self._rt:
            match event.type:
                case "input_audio_buffer.speech_started":
                    self._last_activity = time.monotonic()
                    if self._turn.response_id is not None and not self._assistant_audible:
                        # The user kept talking after OpenAI decided the turn was over.
                        await self._rt.response.cancel()
                    await self._set_phase(Phase.LISTENING)
                case "input_audio_buffer.speech_stopped":
                    await self._set_phase(Phase.THINKING)
                case "response.created":
                    self._turn = _Turn(response_id=event.response.id)
                case "response.output_audio.delta":
                    self._on_audio_delta(event.item_id, event.delta)
                case "response.function_call_arguments.done":
                    self._turn.tool_calls.append((event.call_id, event.name, event.arguments))
                case "response.done":
                    calls = self._turn.tool_calls
                    self._turn = _Turn()
                    if calls:
                        asyncio.create_task(self._run_tools(calls))
                case "conversation.item.input_audio_transcription.completed":
                    log.info("user: %s", event.transcript)
                case "response.output_audio_transcript.done":
                    log.info("assistant: %s", event.transcript)
                case "error":
                    # Cancelling a response that already finished races benignly.
                    level = logging.DEBUG if event.error.code == "response_cancel_not_active" else logging.ERROR
                    log.log(level, "openai error: %s (%s)", event.error.message, event.error.code)
        self._end(EndReason.OPENAI_GONE)

    def _on_audio_delta(self, item_id: str, delta_b64: str) -> None:
        if item_id in self._silenced_items:
            return
        samples = np.frombuffer(base64.b64decode(delta_b64), dtype="<i2").astype(np.int16)
        if self._item is None or self._item.item_id != item_id:
            self._item = _AssistantItem(item_id, stream_start=self._sent_samples + self._pending_samples)
        self._item.samples += len(samples)
        self._pending.append(samples)
        self._pending_samples += len(samples)

    async def _run_tools(self, calls: list[tuple[str, str, str]]) -> None:
        assert self._rt is not None
        self._tools_running += 1
        self._interrupted_since_tools = False
        try:
            await self._set_phase(Phase.THINKING)
            outputs = await asyncio.gather(*(self._hub.call(name, arguments) for _, name, arguments in calls))
            for (call_id, name, _), output in zip(calls, outputs, strict=True):
                log.info("tool %s -> %d chars", name, len(output))
                await self._rt.conversation.item.create(
                    item={"type": "function_call_output", "call_id": call_id, "output": output}
                )
            # If the user interrupted meanwhile, their new turn produces the
            # next response and sees these outputs.
            if not self._interrupted_since_tools:
                await self._rt.response.create()
        finally:
            self._tools_running -= 1
            self._last_activity = time.monotonic()

    # -- limits --------------------------------------------------------------

    async def _watchdog(self, started: float) -> None:
        while True:
            await asyncio.sleep(0.5)
            now = time.monotonic()
            if now - started > self._config.max_conversation_s:
                self._end(EndReason.MAX_DURATION)
                return
            busy = self._assistant_audible or self._turn.response_id is not None or self._tools_running
            if not busy and now - self._last_activity > self._config.idle_timeout_s:
                self._end(EndReason.IDLE)
                return
