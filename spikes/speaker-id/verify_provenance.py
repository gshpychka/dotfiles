import hashlib
import json
from pathlib import Path

import onnx

p = json.loads((Path(__file__).parent / "provenance.json").read_text())["weights"]
a = Path(".speaker-id-cache/model.onnx")
b = Path(".speaker-id-cache/upstream.onnx")
assert hashlib.sha256(a.read_bytes()).hexdigest() == p["artifact_sha256"]
assert hashlib.sha256(b.read_bytes()).hexdigest() == p["upstream_sha256"]
x, y = onnx.load(a), onnx.load(b)
assert x.graph.SerializeToString() == y.graph.SerializeToString()
assert list(x.opset_import) == list(y.opset_import)
assert {m.key: m.value for m in x.metadata_props}["framework"] == "wespeaker"
print(
    "Pinned official upstream graph matches Sherpa artifact exactly; metadata-only adaptation."
)
