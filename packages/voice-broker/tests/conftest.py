from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
from voice_broker.config import Config, Live, OpenClaw


@pytest.fixture
def make_config(tmp_path: Path):
    def make(**overrides) -> Config:
        fields = {
            "listen_host": "127.0.0.1",
            "listen_port": 0,
            "device_token": "token",
            "openai_api_key": "key",
            "devices": [],
            "live": Live(model="gpt-live-1", voice="marin", instructions=""),
            "openclaw": OpenClaw(url="http://openclaw.test", token="gateway-secret", instructions="", model=None),
            "idle_timeout_s": 1.0,
            "max_conversation_s": 30.0,
            "recordings_dir": None,
        }
        fields.update(overrides)
        return Config(**fields)

    return make


def speechlike(n: int, rate: int, seed: int) -> np.ndarray:
    """Band-limited noise with a syllable-rate envelope, as int16."""
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    # Crude low-pass to keep energy in the voice band.
    kernel = np.hanning(9)
    noise = np.convolve(noise, kernel / kernel.sum(), mode="same")
    t = np.arange(n) / rate
    envelope = 0.55 + 0.45 * np.sin(2 * np.pi * 4 * t)
    signal = noise * envelope
    return (signal / np.max(np.abs(signal)) * 12000).astype(np.int16)


def rms_dbfs(samples: np.ndarray) -> float:
    if len(samples) == 0:
        return -120.0
    rms = float(np.sqrt(np.mean(np.square(samples.astype(np.float64)))))
    return 20 * np.log10(max(rms, 1e-3) / 32768.0)
