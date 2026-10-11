"""End-to-end: a simulated device and a scripted Live session.

The simulated device plays whatever the broker sends in real time, reports
PLAYED like ESPHome's DAC callback does, and captures mic audio that is the
played audio's echo plus a person starting to talk mid-reply.
"""

from __future__ import annotations

import asyncio
import base64
from contextlib import asynccontextmanager
from types import SimpleNamespace

import numpy as np
from conftest import speechlike
from voice_broker._aec import EchoCanceller
from voice_broker.conversation import Conversation, EndReason
from voice_broker.live import LiveSession
from voice_broker.mcp_hub import McpHub
from voice_broker.protocol import (
    MIC_RATE,
    SPEAKER_RATE,
    ControlType,
    Kind,
    encode_mic,
    encode_played,
    parse_control,
)

TICK_S = 0.016
SPEAKER_TICK = int(SPEAKER_RATE * TICK_S)
MIC_TICK = int(MIC_RATE * TICK_S)
ECHO_GAIN = 0.05


class SimDevice:
    def __init__(self, talk_after_s: float) -> None:
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

    @property
    def playing(self) -> bool:
        return len(self._playback) > 0

    @property
    def played_total(self) -> int:
        return self._played_total

    async def _tick(self) -> None:
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
            if self._played_total >= self._talk_after_s * SPEAKER_RATE:
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

    async def close(self) -> None:
        self.closed = True
        await self._inbox.put(None)
        self._task.cancel()


def speech_deltas(seconds: float, seed: int) -> list[SimpleNamespace]:
    audio = speechlike(int(SPEAKER_RATE * seconds), SPEAKER_RATE, seed=seed)
    return [
        SimpleNamespace(
            type="session.output_audio.delta",
            delta=base64.b64encode(audio[i : i + SPEAKER_RATE // 10].astype("<i2").tobytes()).decode(),
        )
        for i in range(0, len(audio), SPEAKER_RATE // 10)
    ]


def response_event(delegation_id: str, **event) -> SimpleNamespace:
    return SimpleNamespace(type="response.event", delegation_id=delegation_id, event=event)


class ScriptedLive:
    """Speaks, delegates one tool call, then speaks the result after response.create.

    Like GPT-Live, the output stream never stops: between utterances it carries
    ±1 LSB silence in real time.
    """

    def __init__(self, device: SimDevice, refuse: bool = False) -> None:
        self.events: asyncio.Queue[SimpleNamespace | None] = asyncio.Queue()
        self.calls: list[tuple[str, dict]] = []
        self._refuse = refuse
        self.appended_while_playing = 0
        self._device = device
        self.session = SimpleNamespace(start=self._start, input_audio=SimpleNamespace(append=self._append))
        self.response = SimpleNamespace(
            create=self._response_create, item=SimpleNamespace(create=self._record("response.item.create"))
        )

    def _record(self, name):
        async def call(**kwargs):
            self.calls.append((name, kwargs))

        return call

    async def _start(self, session) -> None:
        self.calls.append(("session.start", {"session": session}))
        if self._refuse:
            error = SimpleNamespace(code="credit_balance_exhausted", message="no credits")
            await self.events.put(SimpleNamespace(type="error", error=error))
            return
        await self.events.put(SimpleNamespace(type="session.started"))
        asyncio.create_task(self._greet_and_delegate())
        asyncio.create_task(self._stream_silence())

    async def _stream_silence(self) -> None:
        chunk = np.tile(np.array([1, -1], dtype="<i2"), SPEAKER_RATE // 20)
        delta = base64.b64encode(chunk.tobytes()).decode()
        while True:
            await asyncio.sleep(0.1)
            await self.events.put(SimpleNamespace(type="session.output_audio.delta", delta=delta))

    async def _append(self, audio: str) -> None:
        if self._device.playing:
            self.appended_while_playing += len(base64.b64decode(audio))

    async def _greet_and_delegate(self) -> None:
        for delta in speech_deltas(1.0, seed=5):
            await self.events.put(delta)
        await self.events.put(
            SimpleNamespace(type="session.delegation.created", delegation=SimpleNamespace(id="dlg_1"))
        )
        await self.events.put(response_event("dlg_1", type="response.created", response={"id": "resp_1"}))
        await self.events.put(
            response_event(
                "dlg_1",
                type="response.output_item.done",
                item={"type": "function_call", "call_id": "call_1", "name": "home__lights", "arguments": "{}"},
            )
        )
        await self.events.put(response_event("dlg_1", type="response.completed", response={"id": "resp_1"}))

    async def _response_create(self) -> None:
        self.calls.append(("response.create", {}))
        await self.events.put(response_event("dlg_1", type="response.created", response={"id": "resp_2"}))
        await self.events.put(response_event("dlg_1", type="response.completed", response={"id": "resp_2"}))
        for delta in speech_deltas(0.5, seed=6):
            await self.events.put(delta)

    def __aiter__(self):
        return self

    async def __anext__(self):
        event = await self.events.get()
        if event is None:
            raise StopAsyncIteration
        return event

    def names(self) -> list[str]:
        return [name for name, _ in self.calls]


def run_live(make_config, refuse: bool = False):
    async def main():
        config = make_config()
        device = SimDevice(talk_after_s=0.3)
        live = ScriptedLive(device, refuse)

        @asynccontextmanager
        async def connect():
            yield live

        session = LiveSession(config.live, "Kitchen", McpHub([]), connect)
        conversation = Conversation(config, "test", device, session, EchoCanceller(MIC_RATE))
        reason = await asyncio.wait_for(conversation.run(), 15)
        return reason, device, live

    return asyncio.run(main())


def test_live_refusal_ends_the_conversation(make_config):
    reason, device, _ = run_live(make_config, refuse=True)
    assert reason == EndReason.OPENAI_GONE
    assert device.controls[-1][0] == ControlType.END


def test_live_streams_the_mic_and_answers_delegated_calls(make_config):
    reason, device, live = run_live(make_config)

    (start,) = [kw["session"] for name, kw in live.calls if name == "session.start"]
    assert start["delegation"]["type"] == "responses"
    # Both the voice and the tool backend know which room the speaker is in.
    assert "in the Kitchen" in start["instructions"]
    assert "in the Kitchen" in start["delegation"]["responses"]["instructions"]
    assert start["audio"]["format"] == {"type": "audio/pcm", "rate": SPEAKER_RATE}

    # Full duplex: the mic keeps streaming while the reply plays.
    assert live.appended_while_playing > 0

    (output,) = [kw["item"] for name, kw in live.calls if name == "response.item.create"]
    assert output["type"] == "function_call_output" and output["call_id"] == "call_1"
    assert live.names().index("response.item.create") < live.names().index("response.create")

    # The greeting and the answer to the tool result both play out in full.
    assert device.played_total >= int(1.5 * SPEAKER_RATE) - SPEAKER_TICK
    phases = [f["phase"] for k, f in device.controls if k == ControlType.PHASE]
    assert "thinking" in phases and "replying" in phases
    # Silence in the stream is not the assistant talking: the phase returns to
    # listening and the conversation idles out.
    assert phases[-1] == "listening"
    assert reason == EndReason.IDLE
