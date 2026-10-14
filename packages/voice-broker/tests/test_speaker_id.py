import threading
import time
from pathlib import Path

import numpy as np
import pytest

from voice_broker.speaker_id import Extractor, Sidecar, Templates, identify


def utterance(s, frames=100, overlap=False):
    for _ in range(frames):
        s.feed(np.full(160, 1000, dtype=np.int16), overlap=overlap)
    s.finish()


def settle(s):
    if s.future:
        s.future.result(timeout=2)
    s.poll()


def test_known_unknown_margin():
    assert identify([1, 0], {"a": [1, 0], "b": [0, 1]}) == "a"
    assert identify([-1, 0], {"a": [1, 0]}) == "unknown"
    assert identify([1, 0], {"a": [1, 0], "b": [1, 0.01]}) == "unknown"


def test_consent_permissions_delete(tmp_path):
    t = Templates(tmp_path / "templates")
    with pytest.raises(ValueError):
        t.enroll("a", [[1, 0]])
    t.enroll("a", [[1, 0]], consent=True)
    assert (tmp_path / "templates/a.json").stat().st_mode & 0o777 == 0o600
    assert t.directory.stat().st_mode & 0o777 == 0o700
    assert list(t.load()) == ["a"]
    with pytest.raises(ValueError):
        t.delete("../escape")
    t.delete("a")
    assert t.load() == {}


def test_checksum_and_license(tmp_path):
    model = tmp_path / "bad"
    model.write_bytes(b"bad")
    with pytest.raises(ValueError, match="CC-BY"):
        Extractor(model)
    with pytest.raises(ValueError, match="checksum"):
        Extractor(model, accept_cc_by_4=True)


def test_default_off():
    s = Sidecar(lambda x: pytest.fail("off engine called"))
    utterance(s)
    assert s.pool is None and s.samples == 0 and s.snapshot() is None


def test_known_and_new_utterance_invalidation():
    s = Sidecar(lambda x: [1, 0], {"a": [1, 0]}, enabled=True)
    utterance(s)
    settle(s)
    assert s.snapshot().label == "a"
    s.feed(np.full(160, 1000, dtype=np.int16))
    assert s.snapshot() is None
    s.close()


@pytest.mark.parametrize("frames,overlap,reason", [(20, False, "too-short"), (100, True, "overlap")])
def test_fallback(frames, overlap, reason):
    s = Sidecar(lambda x: pytest.fail("must not infer"), enabled=True)
    utterance(s, frames, overlap)
    assert s.snapshot().label == "unknown" and s.snapshot().reason == reason
    s.close()


def test_deadline_overload_nonblocking():
    gate = threading.Event()

    def blocked(x):
        gate.wait(2)
        return [1, 0]

    s = Sidecar(blocked, {"a": [1, 0]}, enabled=True, deadline=0.01)
    try:
        utterance(s)
        time.sleep(0.02)
        assert s.snapshot().reason == "deadline"
        start = time.monotonic()
        utterance(s)
        assert time.monotonic() - start < 0.2
        assert s.snapshot().reason == "overload"
        gate.set()
        settle(s)
        assert s.snapshot().reason == "overload"  # late result cannot override latest
    finally:
        gate.set()
        s.close()


def test_error_unknown():
    def bad(x):
        raise RuntimeError("unavailable")

    s = Sidecar(bad, enabled=True)
    utterance(s)
    try:
        settle(s)
    except RuntimeError:
        s.poll()
    assert s.snapshot().reason == "error"
    s.close()


def test_vad_bounded_and_stale():
    s = Sidecar(lambda x: [1, 0], enabled=True)
    for _ in range(500):
        s.feed(np.full(160, 1000, dtype=np.int16))
    assert not s.parts and s.seq == 1
    settle(s)
    for _ in range(101):
        s.feed(np.zeros(160, dtype=np.int16))
    assert s.snapshot() is None
    s.close()


def test_live_delegation_advisory_and_default():
    from types import SimpleNamespace

    from voice_broker.config import Live
    from voice_broker.live import LiveSession
    from voice_broker.speaker_id import Result

    s = LiveSession(Live(model="gpt-live-1", voice="marin", instructions=""), "Kitchen", None, None)
    s._host = SimpleNamespace()
    assert "Local advisory" not in s._task([("user", "hello")])
    s._host.speaker_advisory = lambda: Result(3, 16000, 48000, "a", "matched")
    task = s._task([("user", "hello")])
    assert "utterance 3" in task and "speaker=a" in task and "never use for authorization" in task


def test_conversation_audio_first_with_blocked_inference(monkeypatch):
    import asyncio
    import sys
    from types import SimpleNamespace

    # Native AEC is a separate existing dependency; inject its interface only
    # for the audio ordering unit test, not a claim of AEC acoustic validation.
    monkeypatch.setitem(sys.modules, "voice_broker._aec", SimpleNamespace(EchoCanceller=object))
    from voice_broker.conversation import Conversation
    from voice_broker.recorder import NullRecorder

    gate = threading.Event()

    def blocked(x):
        gate.wait(2)
        return [1, 0]

    side = Sidecar(blocked, enabled=True)
    order = []

    async def mic(x):
        order.append("live")

    original = side.feed

    def feed(x, **kw):
        order.append("tap")
        original(x, **kw)

    side.feed = feed
    c = object.__new__(Conversation)
    c._aec = SimpleNamespace(process_reverse=lambda x: None, process_capture=lambda x: x.tobytes())
    c._recorder = NullRecorder()
    c._session = SimpleNamespace(on_mic=mic)
    c._speaker_id = side
    c._pending_samples = 0
    c._aligner = SimpleNamespace(in_flight_speaker_samples=0)
    c._sound_end = None
    block = SimpleNamespace(reference=np.zeros(160, dtype=np.int16), mic=np.full(160, 1000, dtype=np.int16))

    async def run():
        for _ in range(130):
            await c._process_block(block)

    try:
        start = time.monotonic()
        asyncio.run(run())
        assert time.monotonic() - start < 0.2
        assert order == ["live", "tap"] * 130
    finally:
        gate.set()
        side.close()


def test_insecure_and_symlink_templates(tmp_path):
    directory = tmp_path / "bad"
    directory.mkdir(mode=0o755)
    directory.chmod(0o755)
    with pytest.raises(ValueError):
        Templates(directory)
    t = Templates(tmp_path / "good")
    (t.directory / "link.json").symlink_to(tmp_path / "target")
    with pytest.raises(ValueError):
        t.load()


def test_invalid_frame_and_shutdown():
    s = Sidecar(lambda x: [1, 0], enabled=True)
    utterance(s)
    settle(s)
    s.feed(np.zeros(159, dtype=np.int16))
    assert s.snapshot() is None and not s.parts
    s.close()
    utterance(s)
    assert s.snapshot() is None


def test_internal_silence_is_not_voiced_duration():
    s = Sidecar(lambda x: pytest.fail("too little speech"), enabled=True)
    for _ in range(4):
        for _ in range(20):
            s.feed(np.full(160, 1000, dtype=np.int16))
        for _ in range(20):
            s.feed(np.zeros(160, dtype=np.int16))
    s.finish()
    assert s.snapshot().reason == "too-short"
    s.close()


def test_recording_guard_and_snapshot_failure():
    from types import SimpleNamespace

    from voice_broker.conversation import Conversation

    with pytest.raises(ValueError, match="recording disabled"):
        Conversation(SimpleNamespace(recordings_dir=Path("/not-opened")), "test", None, None, None, speaker_id=object())
    c = object.__new__(Conversation)

    def broken():
        raise RuntimeError("optional failure")

    c._speaker_id = SimpleNamespace(snapshot=broken)
    assert c.speaker_advisory() is None
