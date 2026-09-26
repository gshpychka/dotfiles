"""AEC3 must remove a linear echo given an aligned reference, and keep the near end."""

import numpy as np
from conftest import speechlike

from realtime_voice._aec import EchoCanceller
from realtime_voice.dsp import rms_dbfs
from realtime_voice.protocol import MIC_RATE

BLOCK = MIC_RATE // 100


def room(far: np.ndarray, delay_ms: int) -> np.ndarray:
    """Echo path: acoustic delay plus a short decaying impulse response."""
    rng = np.random.default_rng(1)
    ir = np.zeros(delay_ms * MIC_RATE // 1000 + 200)
    ir[delay_ms * MIC_RATE // 1000] = 0.6
    ir[-200:] += rng.standard_normal(200) * 0.02 * np.exp(-np.arange(200) / 40)
    return np.convolve(far.astype(np.float64), ir)[: len(far)]


def run(far: np.ndarray, mic: np.ndarray) -> np.ndarray:
    aec = EchoCanceller(MIC_RATE)
    out = []
    for i in range(0, len(mic) - BLOCK + 1, BLOCK):
        aec.process_reverse(far[i : i + BLOCK])
        out.append(np.frombuffer(aec.process_capture(mic[i : i + BLOCK]), dtype=np.int16))
    return np.concatenate(out)


def test_cancels_echo_and_keeps_near_end():
    seconds = 8
    n = seconds * MIC_RATE
    far = speechlike(n, MIC_RATE, seed=2)
    echo = room(far, delay_ms=40)
    near = np.zeros(n)
    near_span = slice(6 * MIC_RATE, 7 * MIC_RATE)
    near[near_span] = speechlike(MIC_RATE, MIC_RATE, seed=3) * 0.5
    mic = np.clip(echo + near, -32768, 32767).astype(np.int16)

    cleaned = run(far, mic)

    # After convergence (seconds 3-5, echo only) the residual is far below the echo.
    converged = slice(3 * MIC_RATE, 5 * MIC_RATE)
    erle = rms_dbfs(mic[converged]) - rms_dbfs(cleaned[converged])
    assert erle > 20, f"ERLE {erle:.1f} dB"

    # Double talk: the near end survives within a few dB.
    near_level = rms_dbfs(near[near_span].astype(np.int16))
    assert abs(rms_dbfs(cleaned[near_span]) - near_level) < 6


def test_passthrough_without_far_end():
    near = speechlike(2 * MIC_RATE, MIC_RATE, seed=4)
    cleaned = run(np.zeros_like(near), near)
    assert abs(rms_dbfs(cleaned[MIC_RATE:]) - rms_dbfs(near[MIC_RATE:])) < 2


def test_rejects_wrong_frame_size():
    aec = EchoCanceller(MIC_RATE)
    try:
        aec.process_capture(np.zeros(BLOCK + 1, dtype=np.int16))
    except ValueError:
        return
    raise AssertionError("expected ValueError")
