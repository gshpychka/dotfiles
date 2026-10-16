import json

import pytest

from voice_broker.replay import main


def test_replay_defaults_to_synthetic_offline(monkeypatch, capsys):
    monkeypatch.setattr("sys.argv", ["voice-broker-replay"])
    main()
    result = json.loads(capsys.readouterr().out)
    assert result["samples"] == 28 and result["mode"] == "shadow_no_actuators"


def test_replay_requires_explicit_api_permission(monkeypatch):
    monkeypatch.setattr("sys.argv", ["voice-broker-replay", "--config", "does-not-exist"])
    with pytest.raises(SystemExit) as e:
        main()
    assert e.value.code == 2


@pytest.mark.parametrize("limit", ["0", "29", "100000"])
def test_replay_caps_api_calls(monkeypatch, limit):
    monkeypatch.setattr("sys.argv", ["voice-broker-replay", "--allow-api", "--limit", limit])
    with pytest.raises(SystemExit) as e:
        main()
    assert e.value.code == 2
