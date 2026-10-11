"""Optional per-conversation recordings for tuning echo cancellation.

Each conversation writes `<stamp>-<device>.wav`: 16 kHz, three channels (raw
mic, the aligned far-end reference, echo-cancelled mic), so the canceller can
be judged offline against what actually happened in the room.
"""

from __future__ import annotations

import time
import wave
from pathlib import Path

import numpy as np

from .protocol import MIC_RATE


class Recorder:
    def __init__(self, directory: Path, device: str) -> None:
        directory.mkdir(parents=True, exist_ok=True)
        stamp = f"{time.strftime('%Y%m%d-%H%M%S')}-{device}"
        self._wav = wave.open(str(directory / f"{stamp}.wav"), "wb")  # noqa: SIM115 - held open until close()
        self._wav.setnchannels(3)
        self._wav.setsampwidth(2)
        self._wav.setframerate(MIC_RATE)

    def block(self, mic: np.ndarray, reference: np.ndarray, cleaned: np.ndarray) -> None:
        self._wav.writeframes(np.stack([mic, reference, cleaned], axis=1).astype("<i2").tobytes())

    def close(self) -> None:
        self._wav.close()


class NullRecorder:
    def block(self, mic: np.ndarray, reference: np.ndarray, cleaned: np.ndarray) -> None:
        pass

    def close(self) -> None:
        pass
