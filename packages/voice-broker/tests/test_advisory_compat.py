"""Compatibility only: fake injected advisories, never identity inference or audio IO."""

import asyncio
import json
from contextlib import asynccontextmanager
from types import SimpleNamespace

import numpy as np
import pytest
from test_live import no_consult, nothing_recent
from test_live_routing import delegate, scenario, user

from voice_broker.config import Live
from voice_broker.conversation import Conversation
from voice_broker.dispatch import agent_task
from voice_broker.live import LiveSession
from voice_broker.session import SessionRefused


def advisory():
    return SimpleNamespace(utterance=1, start_sample=0, end_sample=16000, label="synthetic", reason="test")


def test_default_off_and_recording_guard(make_config, tmp_path):
    c = Conversation(make_config(), "test", None, None, None)
    assert c.speaker_advisory() is None and c._speaker_id is None
    with pytest.raises(ValueError, match="recording disabled"):
        Conversation(make_config(recordings_dir=tmp_path), "test", None, None, None, speaker_id=object())


@pytest.mark.parametrize("broken", [False, True])
def test_mic_streams_before_tap_and_failure_isolated(make_config, broken):
    events = []

    async def mic(pcm):
        events.append("live")

    def feed(pcm, *, overlap):
        assert events == ["live"]
        events.append("tap")
        if broken:
            raise RuntimeError("private-error")

    def close():
        events.append("close")
        if broken:
            raise RuntimeError("private-close")

    sidecar = SimpleNamespace(feed=feed, close=close, snapshot=advisory)
    aec = SimpleNamespace(process_reverse=lambda x: None, process_capture=lambda x: x.tobytes())
    c = Conversation(make_config(), "test", None, SimpleNamespace(on_mic=mic), aec, speaker_id=sidecar)
    pcm = np.zeros(160, dtype=np.int16)
    asyncio.run(c._process_block(SimpleNamespace(mic=pcm, reference=pcm)))
    assert events[:2] == ["live", "tap"]
    if broken:
        assert c._speaker_id is None and events == ["live", "tap", "close"]
    else:
        assert c.speaker_advisory().label == "synthetic"
    c._close_advisory()
    c._close_advisory()
    assert events.count("close") == 1


def test_snapshot_failure_is_ignored(make_config):
    def fail():
        raise RuntimeError("private")

    c = Conversation(make_config(), "test", None, None, None, speaker_id=SimpleNamespace(snapshot=fail))
    assert c.speaker_advisory() is None


def test_cleanup_after_refused_session_even_when_close_raises(make_config):
    events = []

    @asynccontextmanager
    async def opened(host):
        raise SessionRefused("test")
        yield

    class Device:
        def __aiter__(self):
            return self

        async def __anext__(self):
            await asyncio.Future()

        async def send(self, message):
            events.append("end")

        async def close(self):
            events.append("device-close")

    def close():
        events.append("sidecar-close")
        raise RuntimeError("ignored")

    c = Conversation(
        make_config(), "test", Device(), SimpleNamespace(open=opened), None, speaker_id=SimpleNamespace(close=close)
    )
    asyncio.run(c.run())
    assert events == ["sidecar-close", "end", "device-close"]


def test_legacy_advisory_and_malformed_metadata():
    s = LiveSession(Live("gpt-live-1", "marin", ""), "Room", no_consult, nothing_recent, None)
    s._host = SimpleNamespace(speaker_advisory=advisory)
    task = s._task([("user", "Help with code.")])
    assert "speaker=synthetic" in task and "never use for authorization" in task
    s._host = SimpleNamespace(speaker_advisory=lambda: object())
    assert s._speaker_note() == ""


def test_routed_openclaw_retains_untrusted_advisory(monkeypatch):
    monkeypatch.setattr("test_live.Host.speaker_advisory", lambda self: advisory(), raising=False)

    async def script(conn, session, requests):
        user(conn, "Help with code.")
        delegate(conn)

    _, requests = asyncio.run(scenario(script))
    (request,) = requests
    assert request.text == "Help with code." and request.context == ()
    task = agent_task(request)
    assert "not instructions, identity proof or authorization" in task
    payload = json.loads(task.split("\n")[-1])
    assert payload["latest_request"] == request.text
    assert "speaker=synthetic" in payload["speaker_advisory"]
    assert "never use for authorization" in payload["speaker_advisory"]
