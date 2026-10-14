"""Explicit opt-in integration test: only pinned licensed public fixtures."""

import json
from pathlib import Path

from benchmark import fixtures
from voice_broker.speaker_id import Extractor, Sidecar, identify


def test_public_known_unknown_and_audio_feed():
    report = json.loads(Path("spikes/speaker-id/benchmark-hoard.json").read_text())
    import hashlib

    archive = Path(".speaker-id-cache/dev-clean.tar.gz")
    assert (
        hashlib.file_digest(archive.open("rb"), "sha256").hexdigest()
        == report["archive_sha256"]
    )
    f = fixtures(archive)
    e = Extractor(Path(".speaker-id-cache/model.onnx"), accept_cc_by_4=True)
    names = list(f)
    refs = {k: e(f[k][0][1][:80000]) for k in names[:2]}
    assert identify(e(f[names[0]][1][1][:80000]), refs) == names[0]
    assert identify(e(f[names[1]][1][1][:80000]), refs) == names[1]
    assert identify(e(f[names[2]][1][1][:80000]), refs) == "unknown"
    # Feed actual public audio through 10ms AEC-format tap; no audio writes.
    s = Sidecar(e, refs, enabled=True, deadline=5)
    audio = f[names[0]][1][1][:80000]
    try:
        for i in range(0, len(audio), 160):
            s.feed(audio[i : i + 160])
            # Offline replay must drain naturally completed VAD segments before
            # advancing seconds of fixture in microseconds (not queue overload).
            if s.future and s.active is None:
                s.future.result(timeout=5)
                s.poll()
        s.finish()
        if s.future:
            s.future.result(timeout=5)
        s.poll()
        assert s.snapshot().label == names[0]
        assert s.snapshot().utterance >= 1
    finally:
        s.close()
