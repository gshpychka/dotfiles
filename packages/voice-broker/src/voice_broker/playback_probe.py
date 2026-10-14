"""Temporary metadata-only probe: no PCM, transcripts, or credentials accepted.
PLAYED counts the resampler's declared INPUT frames, not the 48 kHz DAC frames.
Rates exclude long report gaps; they are evidence, not automatic diagnoses.
"""
from __future__ import annotations
from dataclasses import dataclass

@dataclass
class PlaybackProbe:
    expected_rate: int = 24000
    total_reported: int = 0
    previous_us: int | None = None
    window_frames: int = 0
    window_us: int = 0
    gaps: int = 0

    def report(self, frames: int, dac_us: int, sent_frames: int) -> dict[str, int | float | bool] | None:
        self.total_reported += frames
        previous, self.previous_us = self.previous_us, dac_us
        if previous is None:
            return None  # first report has no interval anchor
        elapsed = dac_us - previous
        expected_us = frames * 1000000 / self.expected_rate
        if elapsed <= 0 or elapsed > max(250000, expected_us * 2):
            self.gaps += 1
            self.window_frames = self.window_us = 0
            return None
        self.window_frames += frames
        self.window_us += elapsed
        if self.window_us < 1000000:
            return None
        result = {
            "expected_input_hz": self.expected_rate,
            "reported_input_hz": round(self.window_frames * 1000000 / self.window_us, 2),
            "window_input_frames": self.window_frames,
            "window_dac_us": self.window_us,
            "sent_input_frames": sent_frames,
            "total_reported_input_frames": self.total_reported,
            "played_exceeds_sent": self.total_reported > sent_frames,
            "discarded_gap_count": self.gaps,
        }
        self.window_frames = self.window_us = 0
        return result
