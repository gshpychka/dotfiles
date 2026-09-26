import pytest

from realtime_voice.protocol import (
    ControlType,
    Kind,
    MicFrame,
    PlayedReport,
    ProtocolError,
    encode_audio,
    encode_control,
    encode_mic,
    encode_played,
    parse_binary,
    parse_control,
)


def test_mic_roundtrip():
    frame = parse_binary(encode_mic(1234, -5, b"\x01\x00\x02\x00"))
    assert frame == MicFrame(1234, -5, b"\x01\x00\x02\x00")


def test_played_roundtrip():
    assert parse_binary(encode_played(960, 10**12)) == PlayedReport(960, 10**12)


def test_audio_kind():
    assert encode_audio(b"ab")[0] == Kind.AUDIO


def test_control_roundtrip():
    kind, fields = parse_control(encode_control(ControlType.PHASE, phase="listening"))
    assert kind == ControlType.PHASE and fields["phase"] == "listening"


@pytest.mark.parametrize(
    "data",
    [b"", b"\x7f", encode_mic(0, 0, b"\x01"), encode_played(1, 1)[:-1]],
)
def test_malformed_binary(data):
    with pytest.raises(ProtocolError):
        parse_binary(data)


def test_malformed_control():
    with pytest.raises(ProtocolError):
        parse_control('{"type": "nope"}')
