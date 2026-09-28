"""The turn-based OpenAI Realtime backend.

While the assistant is audible, mic audio is *not* sent to OpenAI: whatever
echo survives cancellation would otherwise be taken as the user speaking. The
session makes the interruption call itself (BargeInDetector), then stops
playback on the device, cancels the response, truncates the assistant's item
to what was actually heard, and replays the preroll so OpenAI hears the
interruption from its start.
"""

from __future__ import annotations

import asyncio
import base64
import logging
from collections.abc import AsyncIterator, Callable
from contextlib import AbstractAsyncContextManager, asynccontextmanager
from dataclasses import dataclass, field

import numpy as np
from openai import AsyncOpenAI
from openai.resources.realtime.realtime import AsyncRealtimeConnection

from .bargein import BargeInDetector
from .config import Realtime
from .dsp import SileroVad, mic_to_speaker_rate
from .mcp_hub import McpHub
from .protocol import SPEAKER_RATE, Phase
from .session import Host, located

log = logging.getLogger(__name__)

# Base64 audio, dozens per second; the recordings hold the same audio.
_AUDIO_EVENTS = frozenset({"response.output_audio.delta"})

# Opens a Realtime connection; injected so tests can substitute OpenAI.
RealtimeConnector = Callable[[], AbstractAsyncContextManager[AsyncRealtimeConnection]]


def realtime_connector(client: AsyncOpenAI, model: str) -> RealtimeConnector:
    return lambda: client.realtime.connect(model=model)


@dataclass
class _Turn:
    response_id: str | None = None
    tool_calls: list[tuple[str, str, str]] = field(default_factory=list)  # call_id, name, arguments


class RealtimeSession:
    def __init__(self, config: Realtime, area: str, hub: McpHub, connect: RealtimeConnector) -> None:
        self._config = config
        self._instructions = located(config.instructions, area)
        self._hub = hub
        self._connect = connect
        self._barge_in = BargeInDetector(config.barge_in, SileroVad(config.vad_model))
        self._to_openai_rate = mic_to_speaker_rate()
        self._rt: AsyncRealtimeConnection | None = None
        self._host: Host | None = None
        self._silenced_items: set[str] = set()
        self._turn = _Turn()
        self._tools_running = 0
        self._interrupted_since_tools = False

    @asynccontextmanager
    async def open(self, host: Host) -> AsyncIterator[None]:
        async with self._connect() as rt:
            self._rt = rt
            self._host = host
            await rt.session.update(session=self._session_config())
            try:
                yield
            finally:
                self._rt = None

    @property
    def busy(self) -> bool:
        return self._turn.response_id is not None or self._tools_running > 0

    def on_playback_finished(self) -> None:
        self._barge_in.reset()

    def _session_config(self) -> dict[str, object]:
        audio_input: dict[str, object] = {
            "format": {"type": "audio/pcm", "rate": SPEAKER_RATE},
            "noise_reduction": {"type": "far_field"},
            # Interruptions are decided locally; see the module docstring.
            "turn_detection": {
                "type": "semantic_vad",
                "eagerness": self._config.turn_eagerness,
                "create_response": True,
                "interrupt_response": False,
            },
        }
        if self._config.transcription_model:
            audio_input["transcription"] = {"model": self._config.transcription_model}
        return {
            "type": "realtime",
            "model": self._config.model,
            "instructions": self._instructions,
            "output_modalities": ["audio"],
            "audio": {
                "input": audio_input,
                "output": {"format": {"type": "audio/pcm", "rate": SPEAKER_RATE}, "voice": self._config.voice},
            },
            "tools": self._hub.function_tools(),
            "tool_choice": "auto",
        }

    # -- mic -----------------------------------------------------------------

    async def on_mic(self, samples: np.ndarray) -> None:
        assert self._host is not None
        if not self._host.assistant_audible:
            await self._send(samples)
            return
        trigger = self._barge_in.feed(samples)
        if trigger is None:
            return
        log.info(
            "barge-in: %d ms speech at %.1f dBFS, p=%.2f", trigger.speech_ms, trigger.level_dbfs, trigger.probability
        )
        self._host.record_event(
            "barge_in",
            speech_ms=trigger.speech_ms,
            level_dbfs=round(trigger.level_dbfs, 1),
            probability=round(trigger.probability, 3),
        )
        await self._interrupt()

    async def _send(self, samples: np.ndarray) -> None:
        if self._rt is None or len(samples) == 0:
            return
        upsampled = self._to_openai_rate(samples)
        if len(upsampled):
            await self._rt.input_audio_buffer.append(audio=base64.b64encode(upsampled.tobytes()).decode())

    async def _interrupt(self) -> None:
        """The user talked over the assistant."""
        assert self._rt is not None and self._host is not None
        heard = await self._host.flush()
        self._interrupted_since_tools = True
        if self._turn.response_id is not None:
            await self._rt.response.cancel()
        if heard is not None:
            # Deltas already in flight from OpenAI for this item must not play.
            self._silenced_items.add(heard.item_id)
            await self._rt.conversation.item.truncate(
                item_id=heard.item_id, content_index=0, audio_end_ms=heard.audio_end_ms
            )
        preroll = self._barge_in.preroll()
        self._barge_in.reset()
        await self._host.set_phase(Phase.LISTENING)
        await self._send(preroll)

    # -- OpenAI side ---------------------------------------------------------

    async def receive(self) -> None:
        assert self._rt is not None and self._host is not None
        async for event in self._rt:
            if event.type not in _AUDIO_EVENTS:
                log.info("openai: %r", event)
            match event.type:
                case "input_audio_buffer.speech_started":
                    self._host.mark_activity()
                    if self._turn.response_id is not None and not self._host.assistant_audible:
                        # The user kept talking after OpenAI decided the turn was over.
                        await self._rt.response.cancel()
                    await self._host.set_phase(Phase.LISTENING)
                case "input_audio_buffer.speech_stopped":
                    await self._host.set_phase(Phase.THINKING)
                case "response.created":
                    self._turn = _Turn(response_id=event.response.id)
                case "response.output_audio.delta":
                    if event.item_id not in self._silenced_items:
                        samples = np.frombuffer(base64.b64decode(event.delta), dtype="<i2").astype(np.int16)
                        self._host.play(samples, event.item_id)
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

    async def _run_tools(self, calls: list[tuple[str, str, str]]) -> None:
        assert self._rt is not None and self._host is not None
        self._tools_running += 1
        self._interrupted_since_tools = False
        try:
            await self._host.set_phase(Phase.THINKING)
            outputs = await asyncio.gather(*(self._hub.call(name, arguments) for _, name, arguments in calls))
            for (call_id, _, _), output in zip(calls, outputs, strict=True):
                await self._rt.conversation.item.create(
                    item={"type": "function_call_output", "call_id": call_id, "output": output}
                )
            # If the user interrupted meanwhile, their new turn produces the
            # next response and sees these outputs.
            if not self._interrupted_since_tools:
                await self._rt.response.create()
        finally:
            self._tools_running -= 1
            self._host.mark_activity()
