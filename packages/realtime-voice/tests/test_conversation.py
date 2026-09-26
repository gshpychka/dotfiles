"""End-to-end: a simulated device and a scripted Realtime session.

The simulated device plays whatever the broker sends in real time, reports
PLAYED like ESPHome's DAC callback does, and captures mic audio that is the
played audio's echo plus, optionally, a person starting to talk mid-reply.
"""

from __future__ import annotations

import asyncio
import base64
from contextlib import asynccontextmanager
from types import SimpleNamespace

import numpy as np
import pytest
from conftest import speechlike

import realtime_voice.conversation as conversation_module
from realtime_voice._aec import EchoCanceller
from realtime_voice.conversation import Conversation, EndReason
from realtime_voice.dsp import rms_dbfs
from realtime_voice.mcp_hub import McpHub
from realtime_voice.protocol import (
    MIC_RATE,
    SPEAKER_RATE,
    ControlType,
    Kind,
    encode_control,
    encode_mic,
    encode_played,
    parse_control,
)

TICK_S = 0.016
SPEAKER_TICK = int(SPEAKER_RATE * TICK_S)
MIC_TICK = int(MIC_RATE * TICK_S)
ECHO_GAIN = 0.05
REPLY_S = 3.0


class LevelVad:
    """Stands in for Silero: synthetic noise isn't speech to a real VAD."""

    WINDOW = 512

    def __init__(self, _model) -> None:
        self._pending = np.zeros(0, dtype=np.int16)

    def reset(self) -> None:
        self._pending = np.zeros(0, dtype=np.int16)

    def __call__(self, samples: np.ndarray) -> list[float]:
        self._pending = np.concatenate([self._pending, samples])
        out = []
        while len(self._pending) >= self.WINDOW:
            window, self._pending = self._pending[: self.WINDOW], self._pending[self.WINDOW :]
            out.append(1.0 if rms_dbfs(window) > -40 else 0.0)
        return out


class SimDevice:
    def __init__(self, talk_after_s: float | None) -> None:
        self._inbox: asyncio.Queue[str | bytes | None] = asyncio.Queue()
        self._playback = np.zeros(0, dtype=np.int16)
        self._talk_after_s = talk_after_s
        self._played_total = 0
        self._near = speechlike(MIC_RATE * 10, MIC_RATE, seed=7) // 2
        self._near_pos = 0
        self._mic_sample = 0
        self.controls: list[tuple[ControlType, dict]] = []
        self.closed = False
        self._task = asyncio.create_task(self._tick())

    async def _tick(self) -> None:
        await self._inbox.put(encode_control(ControlType.START, wake_word="test"))
        # Timestamps come from the sample clock, as on the device where both
        # I2S buses run off one crystal; asyncio.sleep overshoot only slows the
        # simulation down, it doesn't skew the clocks.
        start_us = 5_000_000
        while not self.closed:
            await asyncio.sleep(TICK_S)
            now_us = start_us + (self._mic_sample + MIC_TICK) * 1_000_000 // MIC_RATE
            played = self._playback[:SPEAKER_TICK]
            self._playback = self._playback[SPEAKER_TICK:]
            if len(played):
                await self._inbox.put(encode_played(len(played), now_us))
                self._played_total += len(played)
            echo = np.zeros(MIC_TICK)
            if len(played):
                x = np.linspace(0, len(played) - 1, int(len(played) * MIC_RATE / SPEAKER_RATE))
                echo[: len(x)] = np.interp(x, np.arange(len(played)), played) * ECHO_GAIN
            mic = echo
            if self._talk_after_s is not None and self._played_total >= self._talk_after_s * SPEAKER_RATE:
                mic = mic + self._near[self._near_pos : self._near_pos + MIC_TICK]
                self._near_pos += MIC_TICK
            pcm = np.clip(mic, -32768, 32767).astype("<i2").tobytes()
            await self._inbox.put(encode_mic(self._mic_sample, now_us - int(TICK_S * 1_000_000), pcm))
            self._mic_sample += MIC_TICK

    def __aiter__(self):
        return self

    async def __anext__(self) -> str | bytes:
        message = await self._inbox.get()
        if message is None:
            raise StopAsyncIteration
        return message

    async def send(self, message: str | bytes) -> None:
        if isinstance(message, bytes):
            assert message[0] == Kind.AUDIO
            self._playback = np.concatenate([self._playback, np.frombuffer(message[1:], dtype="<i2")])
            return
        kind, fields = parse_control(message)
        self.controls.append((kind, fields))
        if kind == ControlType.FLUSH:
            self._playback = np.zeros(0, dtype=np.int16)
            await self._inbox.put(encode_control(ControlType.FLUSHED))

    async def close(self) -> None:
        self.closed = True
        await self._inbox.put(None)
        self._task.cancel()


class ScriptedRealtime:
    """Replies once with REPLY_S of audio; response.done comes late, like a long answer."""

    def __init__(self) -> None:
        self.events: asyncio.Queue[SimpleNamespace | None] = asyncio.Queue()
        self.calls: list[tuple[str, dict]] = []
        self.appended_after_cancel = 0
        self._cancelled = False
        self.session = SimpleNamespace(update=self._record("session.update"))
        self.input_audio_buffer = SimpleNamespace(append=self._append)
        self.response = SimpleNamespace(cancel=self._cancel, create=self._record("response.create"))
        self.conversation = SimpleNamespace(
            item=SimpleNamespace(truncate=self._record("item.truncate"), create=self._record("item.create"))
        )

    def _record(self, name):
        async def call(**kwargs):
            self.calls.append((name, kwargs))
            if name == "session.update":
                asyncio.create_task(self._reply())

        return call

    async def _append(self, audio: str) -> None:
        if self._cancelled:
            self.appended_after_cancel += len(base64.b64decode(audio))

    async def _cancel(self) -> None:
        self.calls.append(("response.cancel", {}))
        self._cancelled = True

    async def _reply(self) -> None:
        await self.events.put(SimpleNamespace(type="response.created", response=SimpleNamespace(id="resp_1")))
        audio = speechlike(int(SPEAKER_RATE * REPLY_S), SPEAKER_RATE, seed=5)
        for i in range(0, len(audio), SPEAKER_RATE // 10):
            delta = base64.b64encode(audio[i : i + SPEAKER_RATE // 10].astype("<i2").tobytes()).decode()
            await self.events.put(SimpleNamespace(type="response.output_audio.delta", item_id="item_1", delta=delta))
        await asyncio.sleep(REPLY_S + 1)
        await self.events.put(SimpleNamespace(type="response.done"))

    def __aiter__(self):
        return self

    async def __anext__(self):
        event = await self.events.get()
        if event is None:
            raise StopAsyncIteration
        return event

    def names(self) -> list[str]:
        return [name for name, _ in self.calls]


async def converse(make_config, monkeypatch, talk_after_s):
    monkeypatch.setattr(conversation_module, "SileroVad", LevelVad)
    realtime = ScriptedRealtime()

    @asynccontextmanager
    async def connect():
        yield realtime

    device = SimDevice(talk_after_s)
    conversation = Conversation(make_config(), McpHub([]), device, connect, EchoCanceller(MIC_RATE))
    reason = await asyncio.wait_for(conversation.run(), timeout=15)
    return reason, device, realtime


def test_user_interrupts_the_reply(make_config, monkeypatch):
    talk_after_s = 1.2
    reason, device, realtime = asyncio.run(converse(make_config, monkeypatch, talk_after_s))

    kinds = [k for k, _ in device.controls]
    assert ControlType.FLUSH in kinds
    assert "response.cancel" in realtime.names()

    (truncate,) = [kw for name, kw in realtime.calls if name == "item.truncate"]
    assert truncate["item_id"] == "item_1"
    heard_ms = truncate["audio_end_ms"]
    # What was heard: up to the interruption plus detection latency, not the
    # whole reply that had already been generated.
    assert talk_after_s * 1000 - 50 <= heard_ms <= talk_after_s * 1000 + 400, heard_ms

    # The interruption itself reached OpenAI (preroll plus what followed).
    assert realtime.appended_after_cancel > 0
    assert reason == EndReason.IDLE


def test_reply_plays_out_without_speech(make_config, monkeypatch):
    reason, device, realtime = asyncio.run(converse(make_config, monkeypatch, talk_after_s=None))
    assert ControlType.FLUSH not in [k for k, _ in device.controls]
    assert "response.cancel" not in realtime.names()
    phases = [f["phase"] for k, f in device.controls if k == ControlType.PHASE]
    assert "replying" in phases and phases[-1] in ("listening", "thinking")
    assert reason == EndReason.IDLE


@pytest.mark.parametrize("seconds", [0.3])
def test_real_vad_ignores_noise(vad_model, seconds):
    from realtime_voice.dsp import SileroVad

    vad = SileroVad(vad_model)
    probabilities = vad(np.random.default_rng(0).integers(-300, 300, int(MIC_RATE * seconds)).astype(np.int16))
    assert probabilities and max(probabilities) < 0.5
