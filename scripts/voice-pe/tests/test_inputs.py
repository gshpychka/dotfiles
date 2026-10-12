"""Check public fetch/source contracts without network or credentials."""

import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
public = json.loads((root / "public-inputs.lock.json").read_text())
assets = json.loads((root / "assets.lock.json").read_text())
python = json.loads((root / "python-inputs.lock.json").read_text())
assert public["format"] == 3 and public["credentialFree"]
assert len(public["components"]) == 12 and len(public["vendor"]) == 3
assert len(assets["models"]) == 5
assert len(python) == 25


def walk(value):
    if isinstance(value, dict):
        if "url" in value:
            assert value["url"].startswith("https://")
            assert re.fullmatch("[0-9a-f]{64}", value["sha256"])
        for child in value.values():
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)


for lock in (public, assets, python):
    walk(lock)
    assert "/nix/store" not in json.dumps(lock)
for source in ("firmware.nix", "project.nix", "python-inputs.nix", "reconstruct.py"):
    text = (root / source).read_text()
    for forbidden in (
        "builtins.storePath",
        "nix-inputs.lock.json",
        "nix-input-roots",
        "voice-pe-validate.",
    ):
        assert forbidden not in text, (source, forbidden)
print("PASS: public hash-locked inputs; no imported snapshot reconstruction dependency")
