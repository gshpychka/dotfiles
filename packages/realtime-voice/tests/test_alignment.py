"""The aligner must put played audio at the mic sample where the DAC emitted it."""

import numpy as np

from realtime_voice.alignment import BLOCK, Aligner
from realtime_voice.protocol import MIC_RATE, SPEAKER_RATE, MicFrame, PlayedReport

US = 1_000_000
T0 = 5_000_000  # esp_timer at the first mic sample
MIC_CHUNK = MIC_RATE * 16 // 1000


def mic_frame(first: int, jitter_us: int = 0) -> MicFrame:
    capture_us = T0 + first * US // MIC_RATE + jitter_us
    return MicFrame(first, capture_us, np.zeros(MIC_CHUNK, dtype=np.int16).tobytes())


def run(aligner: Aligner, played_at_mic: int, audio16: np.ndarray, report_jitter_us: int = 0):
    """Feed 1 s of mic and a playback of `audio16` whose first sample left the DAC at mic index `played_at_mic`."""
    speaker_total = len(audio16) * SPEAKER_RATE // MIC_RATE
    aligner.add_sent(speaker_total, audio16)
    rng = np.random.default_rng(0)
    reported = 0
    blocks = []
    for first in range(0, MIC_RATE, MIC_CHUNK):
        # Capture timestamps are late by up to 3 ms of scheduling delay.
        aligner.add_mic(mic_frame(first, int(rng.integers(0, 3000))))
        now_mic = first + MIC_CHUNK
        # The DAC reports whatever finished playing by now, every 16 ms.
        played16 = min(len(audio16), max(0, now_mic - played_at_mic))
        played_speaker = played16 * SPEAKER_RATE // MIC_RATE
        if played_speaker > reported:
            dac_us = T0 + (played_at_mic + played16) * US // MIC_RATE + int(rng.integers(-report_jitter_us, report_jitter_us + 1))
            aligner.add_played(PlayedReport(played_speaker - reported, dac_us))
            reported = played_speaker
        blocks.extend(aligner.blocks())
    return blocks


def reconstructed(blocks) -> np.ndarray:
    return np.concatenate([b.reference for b in blocks])


def test_reference_lands_at_dac_time():
    audio = np.arange(1, 4001, dtype=np.int16)  # 250 ms ramp, easy to locate
    blocks = run(Aligner(), played_at_mic=3200, audio16=audio)
    ref = reconstructed(blocks)
    start = int(np.argmax(ref != 0))
    # Capture jitter is absorbed by taking the earliest offset; stay within 1 ms.
    assert abs(start - 3200) <= MIC_RATE // 1000
    assert np.count_nonzero(ref) >= len(audio) - MIC_RATE // 1000


def test_report_jitter_does_not_tear_the_run():
    audio = np.arange(1, 8001, dtype=np.int16)
    blocks = run(Aligner(), played_at_mic=1600, audio16=audio, report_jitter_us=2000)
    ref = reconstructed(blocks)
    nz = np.flatnonzero(ref)
    # One continuous run: consecutive reference samples step by one.
    steps = np.diff(ref[nz[0] : nz[-1] + 1].astype(np.int32))
    assert np.mean(steps == 1) > 0.99


def test_blocks_wait_for_reports_while_playing():
    aligner = Aligner()
    aligner.add_sent(2400, np.ones(1600, dtype=np.int16))
    aligner.add_mic(mic_frame(0))
    # Audio is in flight and nothing reported yet: the block must wait.
    assert list(aligner.blocks()) == []


def test_blocks_flow_when_idle():
    aligner = Aligner()
    aligner.add_mic(mic_frame(0))
    blocks = list(aligner.blocks())
    assert len(blocks) == MIC_CHUNK // BLOCK
    assert all(not b.reference.any() for b in blocks)


def test_mic_gap_is_zero_filled():
    aligner = Aligner()
    aligner.add_mic(mic_frame(0))
    aligner.add_mic(mic_frame(2 * MIC_CHUNK))
    assert aligner.dropped_mic_samples == MIC_CHUNK
    assert len(list(aligner.blocks())) == 3 * MIC_CHUNK // BLOCK


def test_flush_ignores_reports_until_acked():
    aligner = Aligner()
    aligner.add_mic(mic_frame(0))
    aligner.add_sent(4800, np.ones(3200, dtype=np.int16))
    aligner.add_played(PlayedReport(960, T0 + 20_000))
    aligner.begin_flush()
    assert aligner.in_flight_speaker_samples == 0
    aligner.add_played(PlayedReport(960, T0 + 40_000))
    assert aligner.played_speaker_samples == 960
    aligner.end_flush()
    aligner.add_sent(960, np.ones(640, dtype=np.int16))
    assert aligner.in_flight_speaker_samples == 960
