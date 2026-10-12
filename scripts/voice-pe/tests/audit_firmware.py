"""Audit built firmware using only known dummy sentinels, never real credentials."""

import json
import subprocess
import sys
from pathlib import Path

output = Path(sys.argv[1])
lock = json.loads((output / "input-lock.json").read_text())
assert lock["format"] == 3 and lock["credentialFree"] and "token" not in lock
assert "no inherited caches" in (output / "codegen-evidence.txt").read_text()
project = Path((output / "pinned-input-paths").read_text().splitlines()[0])
main = (project / "src/main.cpp").read_text()
api = (project / "src/esphome/components/api/api_connection.cpp").read_text()
assert "voice_broker_authenticated_noise_ = parent->get_noise_ctx().has_psk();" in api
dispatch = api[api.index("void APIConnection::on_execute_service_request(") :]
assert dispatch.index(
    "if (!this->voice_broker_authenticated_noise_) return;"
) < dispatch.index("service->execute_service")
for forbidden in (
    "set_token(",
    "set_ssid(",
    "set_password(",
    "set_noise_psk(",
    "set_api_password(",
):
    assert forbidden not in main, forbidden
for name in ("firmware.bin", "home-assistant-voice.elf"):
    data = (output / name).read_bytes()
    for sentinel in (b"validation-only-not-a-credential", b"dummy-A", b"dummy-B"):
        assert sentinel not in data
assert "no network routes" in (output / "offline-evidence.txt").read_text()
subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=output, check=True)
print(
    "PASS: credential-free codegen, dummy sentinel absence, checksums and offline evidence"
)
