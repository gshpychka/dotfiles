"""Resampling between the mic and speaker rates."""

from __future__ import annotations

import numpy as np
import soxr

from .protocol import MIC_RATE, SPEAKER_RATE


class Resampler:
    """Streaming int16 mono resampler."""

    def __init__(self, in_rate: int, out_rate: int) -> None:
        self._stream = soxr.ResampleStream(in_rate, out_rate, 1, dtype="int16", quality="HQ")

    def __call__(self, samples: np.ndarray) -> np.ndarray:
        return self._stream.resample_chunk(samples)


def speaker_to_mic_rate() -> Resampler:
    return Resampler(SPEAKER_RATE, MIC_RATE)


def mic_to_speaker_rate() -> Resampler:
    return Resampler(MIC_RATE, SPEAKER_RATE)
