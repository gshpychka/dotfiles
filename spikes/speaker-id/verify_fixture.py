import hashlib
import json
from pathlib import Path

report = json.loads(Path("spikes/speaker-id/provenance.json").read_text())["fixtures"]
archive = Path(".speaker-id-cache/dev-clean.tar.gz")
assert (
    hashlib.file_digest(archive.open("rb"), "sha256").hexdigest()
    == report["archive_sha256"]
)
print("Licensed public fixture archive checksum matches recorded benchmark.")
