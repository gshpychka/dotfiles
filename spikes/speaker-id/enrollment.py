"""Offline explicit enrollment/deletion. Never records; no audio copied."""

import argparse
from pathlib import Path

import soundfile as sf
from voice_broker.speaker_id import Extractor, Templates

p = argparse.ArgumentParser()
p.add_argument("action", choices=["enroll", "delete"])
p.add_argument("--directory", type=Path, required=True)
p.add_argument("--label", required=True)
p.add_argument("--model", type=Path)
p.add_argument("--consent-local-biometric-template", action="store_true")
p.add_argument("--accept-cc-by-4", action="store_true")
p.add_argument("audio", nargs="*", type=Path)
a = p.parse_args()
t = Templates(a.directory)
if a.action == "delete":
    t.delete(a.label)
else:
    if not a.consent_local_biometric_template or not a.audio:
        p.error(
            "informed consent and existing consented audio required; never use debug recordings"
        )
    e = Extractor(a.model, accept_cc_by_4=a.accept_cc_by_4)
    vectors = []
    for path in a.audio:
        pcm, rate = sf.read(path, dtype="int16")
        if rate != 16000 or pcm.ndim != 1:
            p.error("requires 16kHz mono")
        vectors.append(e(pcm))
    t.enroll(a.label, vectors, consent=True)
print(a.action + " complete; no audio persisted")
