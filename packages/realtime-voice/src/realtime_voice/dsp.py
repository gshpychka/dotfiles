"""Resampling and voice activity detection."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import onnxruntime
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


class SileroVad:
    """Silero VAD (v5+ ONNX graph) at 16 kHz.

    The graph takes 512 new samples plus the last 64 samples of the previous
    window as context, and carries a recurrent state between calls. Mirrors
    silero_vad.utils_vad.OnnxWrapper, minus torch.
    """

    WINDOW = 512
    _CONTEXT = 64

    def __init__(self, model_path: Path) -> None:
        options = onnxruntime.SessionOptions()
        options.inter_op_num_threads = 1
        options.intra_op_num_threads = 1
        self._session = onnxruntime.InferenceSession(
            str(model_path), sess_options=options, providers=["CPUExecutionProvider"]
        )
        self._sr = np.array(MIC_RATE, dtype=np.int64)
        self._pending = np.zeros(0, dtype=np.float32)
        self.reset()

    def reset(self) -> None:
        self._state = np.zeros((2, 1, 128), dtype=np.float32)
        self._context = np.zeros(self._CONTEXT, dtype=np.float32)
        self._pending = np.zeros(0, dtype=np.float32)

    def __call__(self, samples: np.ndarray) -> list[float]:
        """Speech probability for every complete 32 ms window in `samples`."""
        self._pending = np.concatenate([self._pending, samples.astype(np.float32) / 32768.0])
        probabilities = []
        while len(self._pending) >= self.WINDOW:
            window = self._pending[: self.WINDOW]
            self._pending = self._pending[self.WINDOW :]
            x = np.concatenate([self._context, window])[np.newaxis, :]
            out, self._state = self._session.run(None, {"input": x, "state": self._state, "sr": self._sr})
            self._context = window[-self._CONTEXT :]
            probabilities.append(float(out[0][0]))
        return probabilities


def rms_dbfs(samples: np.ndarray) -> float:
    if len(samples) == 0:
        return -120.0
    rms = float(np.sqrt(np.mean(np.square(samples.astype(np.float64)))))
    return 20 * np.log10(max(rms, 1e-3) / 32768.0)
