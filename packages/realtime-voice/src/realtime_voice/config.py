"""Broker configuration, read from one JSON file.

Secrets are never inline: the file names paths (systemd credentials in
production) and they are read at startup.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


def _read_secret(path: str) -> str:
    return Path(path).read_text().strip()


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
class Config:
    listen_host: str
    listen_port: int
    device_token: str
    openai_api_key: str
    model: str
    voice: str
    instructions: str
    transcription_model: str | None
    vad_model: Path
    barge_in: BargeIn
    # Conversation ends after this long with nobody speaking and nothing playing.
    idle_timeout_s: float
    # Hard cap on one conversation, against sessions stuck open and billing.
    max_conversation_s: float
    # When set, every conversation's mic, reference and echo-cancelled audio
    # is written here for tuning the barge-in thresholds.
    recordings_dir: Path | None
    mcp_servers: list[McpServer]


def _header_value(value: str | dict[str, str]) -> str:
    if isinstance(value, str):
        return value
    return value.get("prefix", "") + _read_secret(value["file"])


def _mcp_server(raw: dict[str, Any]) -> McpServer:
    transport = raw["transport"]
    match transport["type"]:
        case "http":
            parsed: HttpServer | StdioServer = HttpServer(
                url=transport["url"],
                headers={k: _header_value(v) for k, v in transport.get("headers", {}).items()},
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


def load(path: Path) -> Config:
    raw = json.loads(path.read_text())
    barge_in = raw["barge_in"]
    return Config(
        listen_host=raw["listen_host"],
        listen_port=int(raw["listen_port"]),
        device_token=_read_secret(raw["device_token_file"]),
        openai_api_key=_read_secret(raw["openai_api_key_file"]),
        model=raw["model"],
        voice=raw["voice"],
        instructions=raw["instructions"],
        transcription_model=raw.get("transcription_model"),
        vad_model=Path(raw["vad_model"]),
        barge_in=BargeIn(
            vad_threshold=float(barge_in["vad_threshold"]),
            min_speech_ms=int(barge_in["min_speech_ms"]),
            min_level_dbfs=float(barge_in["min_level_dbfs"]),
            preroll_ms=int(barge_in["preroll_ms"]),
        ),
        idle_timeout_s=float(raw["idle_timeout_s"]),
        max_conversation_s=float(raw["max_conversation_s"]),
        recordings_dir=Path(raw["recordings_dir"]) if raw.get("recordings_dir") else None,
        mcp_servers=[_mcp_server(s) for s in raw["mcp_servers"]],
    )
