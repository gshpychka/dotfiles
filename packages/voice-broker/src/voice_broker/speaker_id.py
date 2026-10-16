"""OFF by default, advisory-only speaker ID. No runtime audio writes or network.
PCM tap is explicitly injected; production config does not instantiate this POC.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import numpy as np

MODEL_SHA256 = "e9848563da86f263117134dfd7ad63c92355b37de492b55e325400c9d9c39012"


def unit(vector):
    v = np.asarray(vector, dtype=np.float32)
    n = np.linalg.norm(v)
    if v.ndim != 1 or not np.isfinite(v).all() or n < 1e-8:
        raise ValueError("invalid embedding")
    return v / n


class Extractor:
    def __init__(self, model: Path, *, accept_cc_by_4: bool = False):
        if not accept_cc_by_4:
            raise ValueError("acknowledge CC-BY-4.0 weight attribution first")
        if hashlib.sha256(model.read_bytes()).hexdigest() != MODEL_SHA256:
            raise ValueError("model checksum mismatch")
        import sherpa_onnx

        self.engine = sherpa_onnx.SpeakerEmbeddingExtractor(
            sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=str(model), num_threads=1, provider="cpu")
        )

    def __call__(self, pcm):
        pcm = np.asarray(pcm)
        if pcm.dtype != np.int16 or pcm.ndim != 1 or len(pcm) < 16000:
            raise ValueError("need >=1 second mono PCM16 at 16kHz")
        stream = self.engine.create_stream()
        stream.accept_waveform(16000, pcm.astype(np.float32) / 32768)
        stream.input_finished()
        if not self.engine.is_ready(stream):
            raise ValueError("not ready")
        return unit(self.engine.compute(stream))


class Templates:
    """Sensitive local vectors. Explicit informed consent, no guessed enrollment."""

    def __init__(self, directory: Path):
        self.directory = directory
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        if directory.is_symlink() or directory.stat().st_mode & 0o077:
            raise ValueError("template directory must be private 0700")

    def _path(self, label):
        if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", label):
            raise ValueError("invalid label")
        return self.directory / (label + ".json")

    def enroll(self, label, vectors, *, consent=False):
        if not consent:
            raise ValueError("explicit informed enrollment consent required")
        v = unit(np.mean([unit(x) for x in vectors], axis=0))
        path = self._path(label)
        # Refuse overwrite: deletion/re-enrollment is explicit. No audio stored.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump({"model_sha256": MODEL_SHA256, "vector": v.tolist()}, f)

    def delete(self, label):
        self._path(label).unlink(missing_ok=True)

    def load(self):
        result = {}
        for p in self.directory.glob("*.json"):
            if p.is_symlink() or p.stat().st_mode & 0o077:
                raise ValueError("insecure template")
            self._path(p.stem)
            fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(fd) as f:
                d = json.load(f)
            if d["model_sha256"] != MODEL_SHA256:
                raise ValueError("template model mismatch")
            result[p.stem] = unit(d["vector"])
        return result


def identify(vector, templates, threshold=0.65, margin=0.15):
    if not -1 <= threshold <= 1 or not 0 <= margin <= 2:
        raise ValueError("invalid threshold or margin")
    scores = sorted(((float(unit(vector) @ unit(v)), name) for name, v in templates.items()), reverse=True)
    if not scores or scores[0][0] < threshold:
        return "unknown"
    if len(scores) > 1 and scores[0][0] - scores[1][0] < margin:
        return "unknown"
    return scores[0][1]


@dataclass(frozen=True)
class Result:
    utterance: int
    start_sample: int
    end_sample: int
    label: str = "unknown"
    reason: str = "pending"


class Sidecar:
    """Single executor, at most one in-flight inference, no queued audio jobs.

    Energy VAD is a POC, NOT an overlap detector. Caller supplies overlap/echo/
    frame-loss suspicion. Max 5s buffering; no waiting/cancellation pretending
    to stop native inference. Late results are discarded, never reused.
    """

    def __init__(self, extractor, templates=None, *, enabled=False, deadline=0.75):
        if not 0 < deadline <= 5:
            raise ValueError("deadline must be in (0,5] seconds")
        self.enabled = enabled
        self.extractor = extractor
        self.templates = dict(templates or {})
        self.deadline = deadline
        self.pool = ThreadPoolExecutor(max_workers=1) if enabled else None
        self.future = None
        self.job = None
        self.samples = 0
        self.seq = 0
        self.active = None
        self.parts = []
        self.silence = 0
        self.voiced_samples = 0
        self.suspect = False
        self.result = None
        self.closed = False

    def feed(self, pcm, *, overlap=False):
        if not self.enabled or self.closed:
            return
        self.poll()
        pcm = np.asarray(pcm)
        if pcm.dtype != np.int16 or pcm.ndim != 1 or len(pcm) != 160:
            self.result = None
            self.parts.clear()
            self.active = None
            return
        start = self.samples
        self.samples += len(pcm)
        voiced = np.sqrt(np.mean(pcm.astype(np.float32) ** 2)) >= 200
        if voiced and self.active is None:
            self.seq += 1
            self.active = Result(self.seq, start, self.samples)
            self.result = None  # invalidate previous speaker immediately
            self.suspect = False
            self.voiced_samples = 0
        if self.active is None:
            return
        self.suspect |= overlap
        self.parts.append(pcm.copy())
        if voiced:
            self.voiced_samples += len(pcm)
        self.silence = 0 if voiced else self.silence + 160
        if self.silence >= 4800 or self.samples - self.active.start_sample >= 80000:
            self.finish()

    def finish(self):
        if not self.enabled or self.closed or self.active is None:
            return
        r = Result(self.active.utterance, self.active.start_sample, self.samples)
        audio = np.concatenate(self.parts)
        voiced_length = len(audio) - self.silence
        self.parts.clear()
        self.active = None
        self.silence = 0
        reason = "overlap" if self.suspect else "too-short" if self.voiced_samples < 16000 else None
        if reason is None and self.future is not None:
            reason = "overload"
        if reason:
            self.result = Result(r.utterance, r.start_sample, r.end_sample, reason=reason)
            return
        self.result = r
        self.job = (r, time.monotonic() + self.deadline)
        self.future = self.pool.submit(self.extractor, audio[:voiced_length])

    def poll(self):
        if self.future is None:
            return
        r, expires = self.job
        expired = time.monotonic() > expires
        current = self.result is not None and self.result.utterance == r.utterance and self.active is None
        if current and expired:
            self.result = Result(r.utterance, r.start_sample, r.end_sample, reason="deadline")
        if self.future.done():
            try:
                label = identify(self.future.result(), self.templates)
                if current and not expired:
                    self.result = Result(
                        r.utterance,
                        r.start_sample,
                        r.end_sample,
                        label,
                        "matched" if label != "unknown" else "threshold",
                    )
            except Exception:  # noqa: BLE001 -- advisory must fail open
                if current and not expired:
                    self.result = Result(r.utterance, r.start_sample, r.end_sample, reason="error")
            self.future = None
            self.job = None

    def snapshot(self):
        if self.closed or not self.enabled:
            return None
        self.poll()
        # Only the latest completed utterance within 1s of its audio end. No
        # transcript alignment claim: advisory time range accompanies the label.
        if self.active is not None or self.result is None or self.samples - self.result.end_sample > 16000:
            return None
        return self.result

    def close(self):
        self.closed = True
        self.parts.clear()
        self.templates.clear()
        self.result = None
        self.future = None
        self.job = None
        if self.pool:
            self.pool.shutdown(wait=False, cancel_futures=True)
