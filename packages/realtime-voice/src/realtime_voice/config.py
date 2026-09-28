"""Broker configuration, read from one JSON file.

Secrets are never inline: the file names paths (systemd credentials in
production) and they are read at startup.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal, cast, get_args


def _read_secret(path: str) -> str:
    return Path(path).read_text().strip()


# OpenAI semantic_vad eagerness: how readily a pause ends the user's turn.
Eagerness = Literal["low", "medium", "high", "auto"]
# Reasoning effort of the Responses model a Live session delegates to.
ReasoningEffort = Literal["none", "minimal", "low", "medium", "high", "xhigh"]


@dataclass(frozen=True, slots=True)
class HttpServer:
    url: str
    headers: dict[str, str]


@dataclass(frozen=True, slots=True)
class StdioServer:
    command: str
    args: tuple[str, ...]
    env: dict[str, str] | None


@dataclass(frozen=True, slots=True)
class McpServer:
    name: str
    transport: HttpServer | StdioServer
    # None exposes every tool the server offers.
    allow_tools: frozenset[str] | None


@dataclass(frozen=True, slots=True)
class BargeIn:
    # Silero speech probability a 32 ms window needs to count as speech.
    vad_threshold: float
    # Consecutive speech needed while the assistant is talking before it yields.
    min_speech_ms: int
    # Echo-cancelled level below which nothing counts as speech, so a quiet
    # echo residual that fools the VAD can't interrupt.
    min_level_dbfs: float
    # Audio from before the trigger that is replayed to OpenAI, so the first
    # syllables of the interruption aren't lost.
    preroll_ms: int


@dataclass(frozen=True, slots=True)
class Realtime:
    """The turn-based OpenAI Realtime backend."""

    model: str
    voice: str
    instructions: str
    turn_eagerness: Eagerness
    transcription_model: str | None
    vad_model: Path
    barge_in: BargeIn


@dataclass(frozen=True, slots=True)
class Delegation:
    """The Responses model a Live session hands tool work to."""

    model: str
    instructions: str
    reasoning_effort: ReasoningEffort


@dataclass(frozen=True, slots=True)
class Live:
    """The full-duplex OpenAI Live backend."""

    model: str
    voice: str
    # How the voice converses and when it delegates; tool workflows belong in
    # the delegation instructions.
    instructions: str
    delegation: Delegation


@dataclass(frozen=True, slots=True)
class Device:
    """A Voice PE allowed to open conversations."""

    name: str
    # The address it connects from.
    address: str
    # The Home Assistant area it stands in.
    area: str


@dataclass(frozen=True, slots=True)
class Config:
    listen_host: str
    listen_port: int
    device_token: str
    openai_api_key: str
    devices: list[Device]
    realtime: Realtime
    live: Live
    # Conversation ends after this long with nobody speaking and nothing playing.
    idle_timeout_s: float
    # Hard cap on one conversation, against sessions stuck open and billing.
    max_conversation_s: float
    # When set, every conversation's mic, reference and echo-cancelled audio
    # is written here for tuning.
    recordings_dir: Path | None
    mcp_servers: list[McpServer]


def _one_of(kind: Any, name: str, value: str) -> str:
    allowed = get_args(kind)
    if value not in allowed:
        raise ValueError(f"{name} must be one of {allowed}, got {value!r}")
    return value


def _maybe_secret(value: str | dict[str, str]) -> str:
    """A literal, or {"file": path, "prefix": str} for values that are credentials.

    URLs can be credentials too: ha-mcp authenticates by a secret URL path.
    """
    if isinstance(value, str):
        return value
    return value.get("prefix", "") + _read_secret(value["file"])


def _mcp_server(raw: dict[str, Any]) -> McpServer:
    transport = raw["transport"]
    match transport["type"]:
        case "http":
            parsed: HttpServer | StdioServer = HttpServer(
                url=_maybe_secret(transport["url"]),
                headers={k: _maybe_secret(v) for k, v in transport.get("headers", {}).items()},
            )
        case "stdio":
            parsed = StdioServer(
                command=transport["command"],
                args=tuple(transport.get("args", [])),
                env=transport.get("env"),
            )
        case other:
            raise ValueError(f"unknown MCP transport {other!r}")
    allow = raw.get("allow_tools")
    return McpServer(raw["name"], parsed, None if allow is None else frozenset(allow))


def _realtime(raw: dict[str, Any]) -> Realtime:
    barge_in = raw["barge_in"]
    return Realtime(
        model=raw["model"],
        voice=raw["voice"],
        instructions=raw["instructions"],
        turn_eagerness=cast(Eagerness, _one_of(Eagerness, "realtime.turn_eagerness", raw["turn_eagerness"])),
        transcription_model=raw.get("transcription_model"),
        vad_model=Path(raw["vad_model"]),
        barge_in=BargeIn(
            vad_threshold=float(barge_in["vad_threshold"]),
            min_speech_ms=int(barge_in["min_speech_ms"]),
            min_level_dbfs=float(barge_in["min_level_dbfs"]),
            preroll_ms=int(barge_in["preroll_ms"]),
        ),
    )


def _live(raw: dict[str, Any]) -> Live:
    delegation = raw["delegation"]
    return Live(
        model=raw["model"],
        voice=raw["voice"],
        instructions=raw["instructions"],
        delegation=Delegation(
            model=delegation["model"],
            instructions=delegation["instructions"],
            reasoning_effort=cast(
                ReasoningEffort,
                _one_of(ReasoningEffort, "live.delegation.reasoning_effort", delegation["reasoning_effort"]),
            ),
        ),
    )


def load(path: Path) -> Config:
    raw = json.loads(path.read_text())
    return Config(
        listen_host=raw["listen_host"],
        listen_port=int(raw["listen_port"]),
        device_token=_read_secret(raw["device_token_file"]),
        openai_api_key=_read_secret(raw["openai_api_key_file"]),
        devices=[Device(d["name"], d["address"], d["area"]) for d in raw["devices"]],
        realtime=_realtime(raw["realtime"]),
        live=_live(raw["live"]),
        idle_timeout_s=float(raw["idle_timeout_s"]),
        max_conversation_s=float(raw["max_conversation_s"]),
        recordings_dir=Path(raw["recordings_dir"]) if raw.get("recordings_dir") else None,
        mcp_servers=[_mcp_server(s) for s in raw["mcp_servers"]],
    )
