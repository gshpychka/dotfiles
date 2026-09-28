"""The full-duplex OpenAI Live backend.

GPT-Live listens while it speaks and decides for itself when to talk, yield or
keep going, so the echo-cancelled mic streams to it continuously and playback
only ever ends when it stops sending audio. Tool work is delegated to a
Responses model; its function calls run on the MCP hub.
"""

from __future__ import annotations

import asyncio
import base64
import logging
from collections.abc import AsyncIterator, Callable
from contextlib import AbstractAsyncContextManager, asynccontextmanager
from typing import Any

import numpy as np
from openai import AsyncOpenAI
from openai.resources.live.live import AsyncLiveConnection
from openai.types.live.session_config_param import SessionConfigParam

from .config import Live
from .dsp import mic_to_speaker_rate
from .mcp_hub import McpHub
from .protocol import SPEAKER_RATE, Phase
from .session import Host, SessionRefused, located

log = logging.getLogger(__name__)

# Base64 audio, dozens per second; the recordings hold the same audio.
_AUDIO_EVENTS = frozenset({"session.output_audio.delta"})
# The Responses API's terminal events for one response.
_RESPONSE_FINISHED = frozenset({"response.completed", "response.failed", "response.incomplete"})

# Opens a Live connection; injected so tests can substitute OpenAI.
LiveConnector = Callable[[], AbstractAsyncContextManager[AsyncLiveConnection]]


def live_connector(client: AsyncOpenAI) -> LiveConnector:
    # A dropped primary WebSocket ends the conversation; the SDK's reconnect
    # would resume mid-sentence with no audio in between.
    return lambda: client.live.connect(max_retries=0)


class LiveSession:
    def __init__(self, config: Live, area: str, hub: McpHub, connect: LiveConnector) -> None:
        self._config = config
        self._area = area
        self._hub = hub
        self._connect = connect
        self._to_openai_rate = mic_to_speaker_rate()
        self._conn: AsyncLiveConnection | None = None
        self._host: Host | None = None
        # Delegated Responses requests that have not finished.
        self._responses: set[str] = set()
        # Function calls requested within each delegation, run once its response is done.
        self._calls: dict[str | None, list[tuple[str, str, str]]] = {}  # call_id, name, arguments
        self._tools_running = 0
        self._user_said: list[str] = []
        self._assistant_said: list[str] = []

    @asynccontextmanager
    async def open(self, host: Host) -> AsyncIterator[None]:
        async with self._connect() as conn:
            self._conn = conn
            self._host = host
            await conn.session.start(session=self._session_config())
            async for event in conn:
                self._log_event(event)
                if event.type == "session.started":
                    break
                if event.type == "error":
                    raise SessionRefused(f"{event.error.message} ({event.error.code})")
            try:
                yield
            finally:
                self._conn = None

    @property
    def busy(self) -> bool:
        return bool(self._responses) or self._tools_running > 0

    def on_playback_finished(self) -> None:
        self._flush_transcripts()

    def _session_config(self) -> SessionConfigParam:
        delegation = self._config.delegation
        return {
            "model": self._config.model,
            "instructions": located(self._config.instructions, self._area),
            "audio": {
                "format": {"type": "audio/pcm", "rate": SPEAKER_RATE},
                "output": {"voice": self._config.voice},
            },
            "delegation": {
                "type": "responses",
                "responses": {
                    "model": delegation.model,
                    "instructions": located(delegation.instructions, self._area),
                    "reasoning": {"effort": delegation.reasoning_effort},
                    # Strict schemas make every parameter required, and HA's
                    # intents reject the empty slots the model then fills in.
                    "tools": [{**tool, "strict": False} for tool in self._hub.function_tools()],
                    "tool_choice": "auto",
                    # https://developers.openai.com/api/docs/guides/live-migration
                    "parallel_tool_calls": False,
                },
            },
        }

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
                    self._host.play(samples, None)
                case "session.input_transcript.delta":
                    self._host.mark_activity()
                    if self._assistant_said:
                        self._flush_transcripts()
                    self._user_said.append(event.delta)
                case "session.output_transcript.delta":
                    if self._user_said:
                        self._flush_transcripts()
                    self._assistant_said.append(event.delta)
                case "session.delegation.created":
                    await self._host.set_phase(Phase.THINKING)
                case "response.event":
                    await self._on_response_event(event.delegation_id, event.event)
                case "session.closed":
                    log.info("live session closed: %s after %.1f s", event.reason, event.usage.seconds)
                    return
                case "error":
                    log.error("openai error: %s (%s)", event.error.message, event.error.code)
        self._flush_transcripts()

    async def _on_response_event(self, delegation_id: str | None, nested: dict[str, Any]) -> None:
        """One streaming event of a delegated Responses request."""
        assert self._host is not None
        match nested.get("type"):
            case "response.created":
                self._responses.add(nested["response"]["id"])
            case "response.output_item.done":
                item = nested["item"]
                if item.get("type") == "function_call":
                    self._calls.setdefault(delegation_id, []).append((item["call_id"], item["name"], item["arguments"]))
            case finished if finished in _RESPONSE_FINISHED:
                response = nested["response"]
                if finished != "response.completed":
                    reason = response.get("error") or response.get("incomplete_details")
                    log.warning("delegated response %s: %s", finished, reason)
                self._responses.discard(response["id"])
                calls = self._calls.pop(delegation_id, [])
                if calls:
                    asyncio.create_task(self._run_tools(calls))
                elif not self.busy and not self._host.assistant_audible:
                    await self._host.set_phase(Phase.LISTENING)

    async def _run_tools(self, calls: list[tuple[str, str, str]]) -> None:
        assert self._conn is not None and self._host is not None
        self._tools_running += 1
        try:
            outputs = await asyncio.gather(*(self._hub.call(name, arguments) for _, name, arguments in calls))
            for (call_id, _, _), output in zip(calls, outputs, strict=True):
                await self._conn.response.item.create(
                    item={"type": "function_call_output", "call_id": call_id, "output": output}
                )
            await self._conn.response.create()
        finally:
            self._tools_running -= 1
            self._host.mark_activity()

    # -- logging -------------------------------------------------------------

    def _log_event(self, event: Any) -> None:
        if event.type not in _AUDIO_EVENTS:
            log.info("openai: %r", event)

    def _flush_transcripts(self) -> None:
        """Transcripts arrive as fragments with no end marker; log each side's run as a line."""
        if self._user_said:
            log.info("user: %s", "".join(self._user_said).strip())
            self._user_said.clear()
        if self._assistant_said:
            log.info("assistant: %s", "".join(self._assistant_said).strip())
            self._assistant_said.clear()
