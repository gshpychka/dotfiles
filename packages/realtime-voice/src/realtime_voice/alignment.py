"""Aligns the far-end (played) audio with the near-end (mic) audio.

The echo canceller needs, for every 10 ms of mic audio, the 10 ms of audio that
was coming out of the speaker at that moment. Network jitter makes the broker's
send times useless for that, so both streams are placed on the device's own
clock instead:

- Mic frames carry a sample counter and the esp_timer time of their first
  sample. Sample counts are exact; the timestamps only anchor the counter to
  esp_timer, and they include task-scheduling delay, so the smallest recent
  (capture_us - samples) offset is the truest one.
- PLAYED reports say "N more samples of the broker's stream finished leaving
  the DAC at time T". Samples of one uninterrupted playback run are spaced
  exactly one sample period apart, so a run is anchored once and then only
  nudged to track clock drift.

Mic and speaker I2S are both clocked by the XMOS chip, so within a
conversation the two sample counters only drift against esp_timer, not against
each other. What remains (DMA depth, DAC and acoustic latency) is a roughly
constant offset that AEC3's own delay estimator absorbs.
"""

from __future__ import annotations

from collections import deque
from collections.abc import Iterator
from dataclasses import dataclass

import numpy as np

from .protocol import MIC_RATE, SPEAKER_RATE, MicFrame, PlayedReport

BLOCK = MIC_RATE // 100  # AEC3 works on 10 ms frames
_US = 1_000_000

# A report that lands further than this from where the current run predicts
# means playback stalled (underrun or flush); start a new run there.
_RUN_BREAK_SAMPLES = MIC_RATE * 15 // 1000
# Fraction of the prediction error folded in per report, to follow drift
# without passing report jitter through.
_DRIFT_GAIN = 1 / 16
# How long a mic block may wait for PLAYED reports covering it. Reports arrive
# once per I2S DMA completion, well under this.
MAX_REFERENCE_WAIT = MIC_RATE * 120 // 1000
# Offsets over this many recent mic frames are considered for the anchor.
_ANCHOR_WINDOW = 64


@dataclass(frozen=True, slots=True)
class AlignedBlock:
    mic_index: int  # first mic sample of the block
    mic: np.ndarray  # int16[BLOCK]
    reference: np.ndarray  # int16[BLOCK], what the speaker played meanwhile


class _GrowableInt16:
    def __init__(self) -> None:
        self._data = np.zeros(MIC_RATE * 10, dtype=np.int16)
        self.length = 0

    def append(self, samples: np.ndarray) -> None:
        end = self.length + len(samples)
        if end > len(self._data):
            grown = np.zeros(max(end, 2 * len(self._data)), dtype=np.int16)
            grown[: self.length] = self._data[: self.length]
            self._data = grown
        self._data[self.length : end] = samples
        self.length = end

    def slice(self, start: int, stop: int) -> np.ndarray:
        return self._data[start:stop]


class Aligner:
    """Feed it mic frames, played reports and the sent stream; iterate aligned blocks."""

    def __init__(self) -> None:
        # Far-end stream, already resampled to MIC_RATE, indexed by stream sample.
        self._sent = _GrowableInt16()
        # Counted at SPEAKER_RATE, the rate the device actually plays; the
        # resampled copy lags by the resampler's delay, which is harmless for
        # the reference but would skew these counts.
        self._sent_speaker = 0
        self._played_speaker = 0
        # Between FLUSH and the device's FLUSHED ack, PLAYED reports describe
        # audio being discarded; they are ignored.
        self._flushing = False

        self._offsets: deque[float] = deque(maxlen=_ANCHOR_WINDOW)
        self._mic_offset_us: float | None = None

        # Reference laid out on the mic sample axis, starting at _ref_base.
        self._ref = np.zeros(0, dtype=np.int16)
        self._ref_base = 0
        # Mic index up to which the reference is final.
        self._ref_known = 0

        self._run_stream_end: int | None = None  # stream16 index where the run is up to
        self._run_mic_end = 0.0  # mic index (fractional) where that stream sample ends

        self._mic = np.zeros(0, dtype=np.int16)
        self._mic_base = 0  # mic index of self._mic[0]
        self._mic_received = 0  # mic index one past the last received sample
        self.dropped_mic_samples = 0

    # -- far-end input -------------------------------------------------------

    def add_sent(self, speaker_samples: int, pcm_mic_rate: np.ndarray) -> None:
        """Audio just queued to the device: its length, and a MIC_RATE copy."""
        self._sent_speaker += speaker_samples
        self._sent.append(pcm_mic_rate)

    @property
    def in_flight_speaker_samples(self) -> int:
        return self._sent_speaker - self._played_speaker

    @property
    def played_speaker_samples(self) -> int:
        return self._played_speaker

    @property
    def flushing(self) -> bool:
        return self._flushing

    def begin_flush(self) -> None:
        """FLUSH was sent: everything not yet played is gone."""
        self._flushing = True
        self._sent_speaker = self._played_speaker
        self._sent.length = min(self._sent.length, self._played_speaker * MIC_RATE // SPEAKER_RATE)
        self._run_stream_end = None

    def end_flush(self) -> None:
        """The device acknowledged the flush; new audio starts from here."""
        self._flushing = False

    def abandon_in_flight(self) -> None:
        """The device stopped reporting; assume what was sent has played."""
        self._played_speaker = self._sent_speaker
        self._run_stream_end = None

    def add_played(self, report: PlayedReport) -> None:
        if self._flushing:
            return
        start16 = self._played_speaker * MIC_RATE // SPEAKER_RATE
        self._played_speaker = min(self._played_speaker + report.frames, self._sent_speaker)
        end16 = min(self._played_speaker * MIC_RATE // SPEAKER_RATE, self._sent.length)
        if end16 <= start16 or self._mic_offset_us is None:
            return
        measured_end = (report.dac_us - self._mic_offset_us) * MIC_RATE / _US

        if self._run_stream_end == start16:
            predicted = self._run_mic_end + (end16 - start16)
            error = measured_end - predicted
            if abs(error) <= _RUN_BREAK_SAMPLES:
                mic_end = predicted + error * _DRIFT_GAIN
            else:
                mic_end = measured_end
        else:
            mic_end = measured_end
        self._run_stream_end = end16
        self._run_mic_end = mic_end

        dst_end = round(mic_end)
        dst_start = dst_end - (end16 - start16)
        self._write_reference(dst_start, self._sent.slice(start16, end16))
        self._ref_known = max(self._ref_known, dst_end)

    def _write_reference(self, dst_start: int, samples: np.ndarray) -> None:
        if dst_start < self._ref_base:
            samples = samples[self._ref_base - dst_start :]
            dst_start = self._ref_base
        if len(samples) == 0:
            return
        end = dst_start + len(samples) - self._ref_base
        if end > len(self._ref):
            self._ref = np.concatenate([self._ref, np.zeros(end - len(self._ref), dtype=np.int16)])
        offset = dst_start - self._ref_base
        self._ref[offset:end] = samples

    # -- near-end input ------------------------------------------------------

    def add_mic(self, frame: MicFrame) -> None:
        samples = np.frombuffer(frame.pcm, dtype="<i2").astype(np.int16)
        self._offsets.append(frame.capture_us - frame.first_sample * _US / MIC_RATE)
        self._mic_offset_us = min(self._offsets)

        if frame.first_sample < self._mic_received:
            # Overlap with audio already received: keep only the new tail.
            skip = self._mic_received - frame.first_sample
            samples = samples[skip:]
        elif frame.first_sample > self._mic_received:
            gap = frame.first_sample - self._mic_received
            self.dropped_mic_samples += gap
            samples = np.concatenate([np.zeros(gap, dtype=np.int16), samples])
        self._mic = np.concatenate([self._mic, samples])
        self._mic_received += len(samples)

    # -- output --------------------------------------------------------------

    def blocks(self) -> Iterator[AlignedBlock]:
        """Yield every mic block whose reference is final (or waited long enough)."""
        while len(self._mic) >= BLOCK:
            start = self._mic_base
            end = start + BLOCK
            nothing_playing = self.in_flight_speaker_samples == 0
            if not (end <= self._ref_known or nothing_playing or self._mic_received - end >= MAX_REFERENCE_WAIT):
                return
            mic = self._mic[:BLOCK].copy()
            self._mic = self._mic[BLOCK:]
            self._mic_base = end
            yield AlignedBlock(start, mic, self._take_reference(start, end))

    def _take_reference(self, start: int, end: int) -> np.ndarray:
        out = np.zeros(BLOCK, dtype=np.int16)
        lo = max(start, self._ref_base)
        hi = min(end, self._ref_base + len(self._ref))
        if hi > lo:
            out[lo - start : hi - start] = self._ref[lo - self._ref_base : hi - self._ref_base]
        # Nothing before `end` will be asked for again.
        drop = min(len(self._ref), max(0, end - self._ref_base))
        self._ref = self._ref[drop:]
        self._ref_base += drop
        return out
