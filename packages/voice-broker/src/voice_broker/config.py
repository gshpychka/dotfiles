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

    # Newest transcript messages read, tool calls and results among them, at most.
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
    # The Home Assistant action that makes it open a conversation.
    call_action: str
    # Its ESPHome device in Home Assistant's device registry, which home
    # requests are run as; None while routing is off.
    home_assistant_device_id: str | None = None


@dataclass(frozen=True, slots=True)
class Routing:
    """Delegated requests split between Home Assistant and OpenClaw (routing.py)."""

    # OpenAI Decisions model that picks the backend.
    model: str
    # Past this, the request is not classified and nothing runs.
    timeout_s: float
    # The Assist pipeline whose conversation agent home requests go to.
    pipeline: str
    # How long a question Home Assistant asked stays answerable. Home
    # Assistant forgets the conversation after 5 minutes idle
    # (helpers/chat_session.py CONVERSATION_TIMEOUT), so it must be shorter.
    pending_question_s: float
    # Quiet after the last transcript fragment before a request counts as
    # complete: Live delegates without marking the end of the utterance.
    settle_s: float


@dataclass(frozen=True, slots=True)
class Calls:
    """How the agent opens conversations on the speakers."""

    # Unix socket its requests arrive on.
    socket: Path
    # Home Assistant, whose device actions ring the speakers.
    home_assistant_url: str
    home_assistant_token: str


@dataclass(frozen=True, slots=True)
class Config:
    listen_host: str
    listen_port: int
    device_token: str
    openai_api_key: str
    devices: list[Device]
    live: Live
    openclaw: OpenClaw
    calls: Calls
    # Conversation ends after this long with nobody speaking and nothing playing.
    idle_timeout_s: float
    # Hard cap on one conversation, against sessions stuck open and billing.
    max_conversation_s: float
    # When set, every conversation's mic, reference and echo-cancelled audio
    # is written here for tuning.
    recordings_dir: Path | None
    # None sends every delegated request to OpenClaw.
    routing: Routing | None = None


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


def _calls(raw: dict[str, Any]) -> Calls:
    return Calls(
        socket=Path(raw["socket"]),
        home_assistant_url=raw["home_assistant_url"],
        home_assistant_token=_read_secret(raw["home_assistant_token_file"]),
    )


def _routing(raw: dict[str, Any]) -> Routing:
    routing = Routing(
        model=raw["model"],
        timeout_s=float(raw["timeout_s"]),
        pipeline=raw["pipeline"],
        pending_question_s=float(raw["pending_question_s"]),
        settle_s=float(raw["settle_s"]),
    )
    if not routing.model or not routing.pipeline:
        raise ValueError("routing needs a model and a pipeline")
    if not 0 < routing.timeout_s <= 10:
        raise ValueError("routing.timeout_s must be in (0, 10]")
    if not 0 < routing.pending_question_s < 300:
        raise ValueError("routing.pending_question_s must be in (0, 300): Home Assistant forgets after 5 minutes")
    # A longer wait would leave the settling cap (live._SETTLE_MAX_S) a single window.
    if not 0 < routing.settle_s <= 1:
        raise ValueError("routing.settle_s must be in (0, 1]")
    return routing


def _device(raw: dict[str, Any]) -> Device:
    return Device(
        raw["name"], raw["address"], raw["area"], raw["call_action"], raw.get("home_assistant_device_id") or None
    )


def load(path: Path) -> Config:
    raw = json.loads(path.read_text())
    devices = [_device(d) for d in raw["devices"]]
    routing = _routing(raw["routing"]) if raw.get("routing") else None
    if routing is not None and (unplaced := [d.name for d in devices if d.home_assistant_device_id is None]):
        raise ValueError(f"routing needs home_assistant_device_id for {', '.join(unplaced)}")
    return Config(
        listen_host=raw["listen_host"],
        listen_port=int(raw["listen_port"]),
        device_token=_read_secret(raw["device_token_file"]),
        openai_api_key=_read_secret(raw["openai_api_key_file"]),
        devices=devices,
        live=_live(raw["live"]),
        openclaw=_openclaw(raw["openclaw"]),
        calls=_calls(raw["calls"]),
        idle_timeout_s=float(raw["idle_timeout_s"]),
        max_conversation_s=float(raw["max_conversation_s"]),
        recordings_dir=Path(raw["recordings_dir"]) if raw.get("recordings_dir") else None,
        routing=routing,
    )
