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


# Leads the identity file's text: the assistant's description of itself.
_IDENTITY_LEAD = "Who you are, in your own words; the backend is your own memory and tools:"


@dataclass(frozen=True, slots=True)
class Live:
    """The full-duplex OpenAI Live backend."""

    model: str
    voice: str
    # How the voice converses and when it delegates, led by who it is when
    # the identity file says so.
    instructions: str


@dataclass(frozen=True, slots=True)
class History:
    """How much of the agent's conversation the voice starts with."""

    # Newest messages read, at most.
    max_messages: int
    # Messages older than this are left out.
    max_age_s: float
    # Text of the messages kept, newest first, at most.
    max_chars: int


@dataclass(frozen=True, slots=True)
class OpenClaw:
    """The OpenClaw gateway that carries out delegated work."""

    # Base URL of the gateway's HTTP endpoints.
    url: str
    # The gateway's shared secret.
    token: str
    # The agent session consults are turns of, and whose transcript the voice starts with.
    session_key: str
    # Added to the agent's own prompt for every consult.
    instructions: str
    # Backend model for consults; None keeps the agent's own.
    model: str | None
    history: History


@dataclass(frozen=True, slots=True)
class Device:
    """A Voice PE allowed to open conversations."""

    name: str
    # The address it connects from.
    address: str
    # The room it stands in.
    area: str


@dataclass(frozen=True, slots=True)
class Config:
    listen_host: str
    listen_port: int
    device_token: str
    openai_api_key: str
    devices: list[Device]
    live: Live
    openclaw: OpenClaw
    # Conversation ends after this long with nobody speaking and nothing playing.
    idle_timeout_s: float
    # Hard cap on one conversation, against sessions stuck open and billing.
    max_conversation_s: float
    # When set, every conversation's mic, reference and echo-cancelled audio
    # is written here for tuning.
    recordings_dir: Path | None


def _live(raw: dict[str, Any]) -> Live:
    instructions = raw["instructions"]
    identity_file = raw.get("identity_file")
    identity = Path(identity_file).read_text().strip() if identity_file else ""
    if identity:
        instructions = f"{_IDENTITY_LEAD}\n{identity}\n\n{instructions}"
    return Live(model=raw["model"], voice=raw["voice"], instructions=instructions)


def _history(raw: dict[str, Any]) -> History:
    return History(
        max_messages=int(raw["max_messages"]),
        max_age_s=float(raw["max_age_s"]),
        max_chars=int(raw["max_chars"]),
    )


def _openclaw(raw: dict[str, Any]) -> OpenClaw:
    return OpenClaw(
        url=raw["url"],
        token=_read_secret(raw["token_file"]),
        session_key=raw["session_key"],
        instructions=raw["instructions"],
        model=raw.get("model"),
        history=_history(raw["history"]),
    )


def load(path: Path) -> Config:
    raw = json.loads(path.read_text())
    return Config(
        listen_host=raw["listen_host"],
        listen_port=int(raw["listen_port"]),
        device_token=_read_secret(raw["device_token_file"]),
        openai_api_key=_read_secret(raw["openai_api_key_file"]),
        devices=[Device(d["name"], d["address"], d["area"]) for d in raw["devices"]],
        live=_live(raw["live"]),
        openclaw=_openclaw(raw["openclaw"]),
        idle_timeout_s=float(raw["idle_timeout_s"]),
        max_conversation_s=float(raw["max_conversation_s"]),
        recordings_dir=Path(raw["recordings_dir"]) if raw.get("recordings_dir") else None,
    )
