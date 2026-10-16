from __future__ import annotations

import json
from pathlib import Path

import pytest
from voice_broker.config import Device, History, Routing, load

ROOM = Device("room-assistant", "192.168.1.54", "Room", "esphome.home_assistant_voice_0914cc_start_conversation")


def write_config(tmp_path: Path, **live: str) -> Path:
    for name in ("device-token", "openai-api-key", "openclaw-secret", "ha-token"):
        (tmp_path / name).write_text("secret\n")
    path = tmp_path / "config.json"
    path.write_text(
        json.dumps(
            {
                "listen_host": "127.0.0.1",
                "listen_port": 0,
                "device_token_file": str(tmp_path / "device-token"),
                "openai_api_key_file": str(tmp_path / "openai-api-key"),
                "devices": [
                    {"name": ROOM.name, "address": ROOM.address, "area": ROOM.area, "call_action": ROOM.call_action}
                ],
                "calls": {
                    "socket": str(tmp_path / "call.sock"),
                    "home_assistant_url": "http://ha.test",
                    "home_assistant_token_file": str(tmp_path / "ha-token"),
                },
                "live": {"model": "gpt-live-1", "voice": "marin", "instructions": "Speak briefly.", **live},
                "openclaw": {
                    "url": "http://openclaw.test",
                    "token_file": str(tmp_path / "openclaw-secret"),
                    "session_key": "agent:main:main",
                    "instructions": "",
                    "history": {"max_messages": 40, "max_age_s": 86400, "max_chars": 8000},
                },
                "idle_timeout_s": 1,
                "max_conversation_s": 30,
            }
        )
    )
    return path


def test_the_speakers_and_the_calls_are_read(tmp_path: Path) -> None:
    config = load(write_config(tmp_path))
    assert config.devices == [ROOM]
    assert config.calls.socket == tmp_path / "call.sock"
    assert config.calls.home_assistant_url == "http://ha.test"
    assert config.calls.home_assistant_token == "secret"


def test_the_agents_session_and_history_bounds_are_read(tmp_path: Path) -> None:
    openclaw = load(write_config(tmp_path)).openclaw
    assert openclaw.session_key == "agent:main:main"
    assert openclaw.history == History(max_messages=40, max_age_s=86400.0, max_chars=8000)


def test_identity_leads_the_instructions(tmp_path: Path) -> None:
    identity = tmp_path / "identity"
    identity.write_text("- **Name:** Calcifer\n")
    instructions = load(write_config(tmp_path, identity_file=str(identity))).live.instructions
    lead, rest = instructions.split("\n", 1)
    assert lead.startswith("Who you are")
    assert rest == "- **Name:** Calcifer\n\nSpeak briefly."


def test_empty_identity_keeps_the_instructions(tmp_path: Path) -> None:
    identity = tmp_path / "identity"
    identity.write_text("\n")
    assert load(write_config(tmp_path, identity_file=str(identity))).live.instructions == "Speak briefly."


def test_no_identity_file_keeps_the_instructions(tmp_path: Path) -> None:
    assert load(write_config(tmp_path)).live.instructions == "Speak briefly."


ROUTING = {
    "model": "gpt-6-luna",
    "timeout_s": 4,
    "pipeline": "01jmq3hbakt5r0e136vd886hy9",
    "pending_question_s": 60,
    "settle_s": 0.35,
}


def with_routing(path: Path, routing: dict | None, device_id: str | None = "9290a2568e3df21ba0fd2d663249c0ca") -> Path:
    raw = json.loads(path.read_text())
    if routing is not None:
        raw["routing"] = routing
    if device_id is not None:
        raw["devices"][0]["home_assistant_device_id"] = device_id
    path.write_text(json.dumps(raw))
    return path


def test_no_routing_keeps_every_request_with_the_agent(tmp_path: Path) -> None:
    config = load(write_config(tmp_path))
    assert config.routing is None and config.devices[0].home_assistant_device_id is None


def test_routing_and_the_speakers_home_assistant_device_are_read(tmp_path: Path) -> None:
    config = load(with_routing(write_config(tmp_path), ROUTING))
    assert config.routing == Routing("gpt-6-luna", 4.0, "01jmq3hbakt5r0e136vd886hy9", 60.0, 0.35)
    assert config.devices[0].home_assistant_device_id == "9290a2568e3df21ba0fd2d663249c0ca"


def test_the_diagnostic_routing_limit_is_accepted(tmp_path: Path) -> None:
    config = load(with_routing(write_config(tmp_path), {**ROUTING, "timeout_s": 30}))
    assert config.routing is not None and config.routing.timeout_s == 30.0


def test_routing_needs_every_speakers_home_assistant_device(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="room-assistant"):
        load(with_routing(write_config(tmp_path), ROUTING, device_id=None))


@pytest.mark.parametrize(
    "change",
    [
        {"pending_question_s": 300},
        {"pending_question_s": 0},
        {"timeout_s": 0},
        # The limit that ran out on a cold request on 2026-10-16.
        {"timeout_s": 1.5},
        {"timeout_s": 2.9},
        {"timeout_s": 30.5},
        {"settle_s": 0},
        {"settle_s": 1.5},
        {"pipeline": ""},
        {"model": ""},
    ],
)
def test_routing_bounds_are_checked(tmp_path: Path, change: dict) -> None:
    with pytest.raises(ValueError):
        load(with_routing(write_config(tmp_path), {**ROUTING, **change}))
