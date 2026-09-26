"""Optional per-conversation recordings for tuning barge-in.

Each conversation writes `<stamp>.wav` (16 kHz, three channels: raw mic, the
aligned far-end reference, echo-cancelled mic) and `<stamp>.jsonl` with the
barge-in decisions and AEC statistics, so thresholds can be tuned offline
against what actually happened in the room.
"""

from __future__ import annotations

import json
import time
import wave
from pathlib import Path
from typing import Any

import numpy as np

from .protocol import MIC_RATE


class Recorder:
    def __init__(self, directory: Path) -> None:
        directory.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        self._wav = wave.open(str(directory / f"{stamp}.wav"), "wb")
        self._wav.setnchannels(3)
        self._wav.setsampwidth(2)
        self._wav.setframerate(MIC_RATE)
        self._events = (directory / f"{stamp}.jsonl").open("w")

    def block(self, mic: np.ndarray, reference: np.ndarray, cleaned: np.ndarray) -> None:
        self._wav.writeframes(np.stack([mic, reference, cleaned], axis=1).astype("<i2").tobytes())

    def event(self, mic_index: int, kind: str, **fields: Any) -> None:
        self._events.write(json.dumps({"t": mic_index / MIC_RATE, "event": kind, **fields}) + "\n")

    def close(self) -> None:
        self._wav.close()
        self._events.close()


class NullRecorder:
    def block(self, mic: np.ndarray, reference: np.ndarray, cleaned: np.ndarray) -> None:
        pass

    def event(self, mic_index: int, kind: str, **fields: Any) -> None:
        pass

    def close(self) -> None:
        pass
