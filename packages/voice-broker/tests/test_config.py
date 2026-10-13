from __future__ import annotations

import json
from pathlib import Path

from voice_broker.config import History, load


def write_config(tmp_path: Path, **live: str) -> Path:
    for name in ("device-token", "openai-api-key", "openclaw-secret"):
        (tmp_path / name).write_text("secret\n")
    path = tmp_path / "config.json"
    path.write_text(
        json.dumps(
            {
                "listen_host": "127.0.0.1",
                "listen_port": 0,
                "device_token_file": str(tmp_path / "device-token"),
                "openai_api_key_file": str(tmp_path / "openai-api-key"),
                "devices": [],
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
