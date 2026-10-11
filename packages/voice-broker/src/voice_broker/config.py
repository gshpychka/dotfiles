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
class Live:
    """The full-duplex OpenAI Live backend."""

    model: str
    voice: str
    # How the voice converses and when it delegates.
    instructions: str


@dataclass(frozen=True, slots=True)
class OpenClaw:
    """The OpenClaw gateway that carries out delegated work."""

    # Base URL of the gateway's HTTP endpoints.
    url: str
    # The gateway's shared secret.
    token: str
    # Added to the agent's own prompt for every consult.
    instructions: str
    # Backend model for consults; None keeps the agent's own.
    model: str | None


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


def _openclaw(raw: dict[str, Any]) -> OpenClaw:
    return OpenClaw(
        url=raw["url"],
        token=_read_secret(raw["token_file"]),
        instructions=raw["instructions"],
        model=raw.get("model"),
    )


def load(path: Path) -> Config:
    raw = json.loads(path.read_text())
    live = raw["live"]
    return Config(
        listen_host=raw["listen_host"],
        listen_port=int(raw["listen_port"]),
        device_token=_read_secret(raw["device_token_file"]),
        openai_api_key=_read_secret(raw["openai_api_key_file"]),
        devices=[Device(d["name"], d["address"], d["area"]) for d in raw["devices"]],
        live=Live(model=live["model"], voice=live["voice"], instructions=live["instructions"]),
        openclaw=_openclaw(raw["openclaw"]),
        idle_timeout_s=float(raw["idle_timeout_s"]),
        max_conversation_s=float(raw["max_conversation_s"]),
        recordings_dir=Path(raw["recordings_dir"]) if raw.get("recordings_dir") else None,
    )
