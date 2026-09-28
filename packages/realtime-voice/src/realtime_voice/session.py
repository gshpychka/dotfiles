"""Interfaces between a conversation and the OpenAI session it runs on."""

from __future__ import annotations

from contextlib import AbstractAsyncContextManager
from dataclasses import dataclass
from typing import Any, Protocol

import numpy as np

from .protocol import Phase


def located(instructions: str, area: str) -> str:
    """Instructions for a speaker in `area`, which unplaced requests refer to."""
    placement = f"This speaker is in the {area}. A request that names no place is about the {area}."
    return f"{instructions.rstrip()}\n\n{placement}\n"


class SessionRefused(Exception):
    """OpenAI rejected the session before it started."""


@dataclass(frozen=True, slots=True)
class Heard:
    """How much of an assistant item reached the room before playback stopped."""

    item_id: str
    audio_end_ms: int


class Host(Protocol):
    """What a model session can do to the conversation it runs in."""

    @property
    def assistant_audible(self) -> bool:
        """Assistant audio is queued or still leaving the speaker."""
        ...

    def play(self, samples: np.ndarray, item_id: str | None) -> None:
        """Queues SPEAKER_RATE audio; item_id names the assistant item it belongs to."""
        ...

    async def flush(self) -> Heard | None:
        """Drops all queued and unplayed audio; reports the item it cut short."""
        ...

    async def set_phase(self, phase: Phase) -> None: ...

    def mark_activity(self) -> None:
        """Someone is speaking or something is happening; restarts the idle timer."""
        ...

    def record_event(self, kind: str, **fields: Any) -> None: ...


class ModelSession(Protocol):
    def open(self, host: Host) -> AbstractAsyncContextManager[None]:
        """Connected and configured, ready for mic audio, while entered."""
        ...

    async def receive(self) -> None:
        """Handles OpenAI events until the connection closes."""
        ...

    async def on_mic(self, samples: np.ndarray) -> None:
        """One echo-cancelled block of MIC_RATE audio."""
        ...

    def on_playback_finished(self) -> None:
        """Assistant audio played out to the end."""
        ...

    @property
    def busy(self) -> bool:
        """A response or tool call is in progress."""
        ...
