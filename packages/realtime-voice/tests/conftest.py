from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import pytest

from realtime_voice.config import BargeIn, Config


@pytest.fixture
def vad_model() -> Path:
    path = os.environ.get("REALTIME_VOICE_VAD_MODEL")
    if not path:
        pytest.skip("REALTIME_VOICE_VAD_MODEL not set")
    return Path(path)


@pytest.fixture
def make_config(tmp_path: Path):
    def make(vad_model: Path = Path("/nonexistent"), **overrides) -> Config:
        fields = dict(
            listen_host="127.0.0.1",
            listen_port=0,
            device_token="token",
            openai_api_key="key",
            model="gpt-realtime-2",
            voice="marin",
            instructions="",
            transcription_model=None,
            vad_model=vad_model,
            barge_in=BargeIn(vad_threshold=0.5, min_speech_ms=96, min_level_dbfs=-50.0, preroll_ms=300),
            idle_timeout_s=1.0,
            max_conversation_s=30.0,
            recordings_dir=None,
            mcp_servers=[],
        )
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
