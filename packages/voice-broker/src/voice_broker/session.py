"""Interfaces between a conversation and the OpenAI session it runs on."""

from __future__ import annotations

from contextlib import AbstractAsyncContextManager
from typing import Protocol

import numpy as np

from .protocol import Phase


def placement(area: str) -> str:
    """Where the speaker is, which unplaced requests refer to."""
    return f"This speaker is in the {area}. A request that names no place is about the {area}."


def located(instructions: str, area: str) -> str:
    """Instructions for a speaker in `area`."""
    return f"{instructions.rstrip()}\n\n{placement(area)}\n"


class SessionRefused(Exception):
    """OpenAI rejected the session before it started."""


class Host(Protocol):
    """What a model session can do to the conversation it runs in."""

    @property
    def assistant_audible(self) -> bool:
        """Assistant audio is queued or still leaving the speaker."""
        ...

    def play(self, samples: np.ndarray) -> None:
        """Queues SPEAKER_RATE audio."""
        ...

    async def set_phase(self, phase: Phase) -> None: ...

    def mark_activity(self) -> None:
        """Someone is speaking or something is happening; restarts the idle timer."""
        ...


class ModelSession(Protocol):
    def open(self, host: Host) -> AbstractAsyncContextManager[None]:
        """Connected and configured, ready for mic audio, while entered."""
        ...

    async def receive(self) -> None:
        """Handles OpenAI events until the connection closes."""
        ...

    async def on_mic(self, samples: np.ndarray) -> None:
        """One echo-cancelled block of MIC_RATE audio, held for the model while the session is not open."""
        ...

    def on_playback_finished(self) -> None:
        """Assistant audio finished playing."""
        ...

    @property
    def busy(self) -> bool:
        """Delegated work is in progress."""
        ...
