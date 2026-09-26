"""Decides when the user is talking over the assistant."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass

import numpy as np

from .alignment import BLOCK
from .config import BargeIn
from .dsp import SileroVad, rms_dbfs
from .protocol import MIC_RATE


@dataclass(frozen=True, slots=True)
class Trigger:
    speech_ms: int
    level_dbfs: float
    probability: float


class BargeInDetector:
    """Watches echo-cancelled mic audio while the assistant is audible.

    Speech has to be sustained (min_speech_ms of consecutive VAD windows over
    threshold) and loud enough to be a person in the room rather than echo
    residual. Keeps a preroll of recent audio so the interruption's first
    syllables can be replayed to OpenAI.
    """

    def __init__(self, config: BargeIn, vad: SileroVad) -> None:
        self._config = config
        self._vad = vad
        self._preroll: deque[np.ndarray] = deque(maxlen=max(1, config.preroll_ms * MIC_RATE // 1000 // BLOCK))
        self._speech_windows = 0
        self._window_ms = SileroVad.WINDOW * 1000 // MIC_RATE
        self._levels: deque[float] = deque(maxlen=SileroVad.WINDOW // BLOCK + 1)

    def reset(self) -> None:
        self._vad.reset()
        self._preroll.clear()
        self._levels.clear()
        self._speech_windows = 0

    def preroll(self) -> np.ndarray:
        if not self._preroll:
            return np.zeros(0, dtype=np.int16)
        return np.concatenate(list(self._preroll))

    def feed(self, cleaned: np.ndarray) -> Trigger | None:
        self._preroll.append(cleaned)
        self._levels.append(rms_dbfs(cleaned))
        trigger = None
        for probability in self._vad(cleaned):
            level = max(self._levels)
            if probability >= self._config.vad_threshold and level >= self._config.min_level_dbfs:
                self._speech_windows += 1
            else:
                self._speech_windows = 0
            speech_ms = self._speech_windows * self._window_ms
            if speech_ms >= self._config.min_speech_ms:
                trigger = Trigger(speech_ms, level, probability)
        return trigger
