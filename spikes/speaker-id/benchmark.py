"""Only OpenSLR12 public CC-BY-4.0 fixtures; no household audio."""

import argparse
import hashlib
import io
import json
import os
import platform
import resource
import subprocess
import sys
import tarfile
import time
from pathlib import Path

import numpy as np
import soundfile as sf
from voice_broker.speaker_id import Extractor, identify


def fixtures(archive):
    chosen = {}
    with tarfile.open(archive) as t:
        for member in t:
            if member.name.endswith(".flac"):
                speaker = member.name.split("/")[2]
                if speaker not in chosen and len(chosen) >= 3:
                    continue
                audio, rate = sf.read(
                    io.BytesIO(t.extractfile(member).read()), dtype="int16"
                )
                if rate != 16000 or audio.ndim != 1 or len(audio) < 80000:
                    continue
                chosen.setdefault(speaker, [])
                if len(chosen[speaker]) < 2:
                    chosen[speaker].append((member.name, audio))
                if len(chosen) == 3 and all(len(v) == 2 for v in chosen.values()):
                    return chosen
    raise ValueError("insufficient fixtures")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", type=Path, required=True)
    p.add_argument("--archive", type=Path, required=True)
    p.add_argument("--child", type=int)
    p.add_argument("--repeats", type=int, default=20)
    a = p.parse_args()
    if not a.child:
        expected = json.loads((Path(__file__).parent / "provenance.json").read_text())[
            "fixtures"
        ]["archive_sha256"]
        actual = hashlib.file_digest(a.archive.open("rb"), "sha256").hexdigest()
        if actual != expected:
            raise ValueError("fixture archive checksum mismatch")
    f = fixtures(a.archive)
    pcm = next(iter(f.values()))[1][1]
    if a.child:
        start = time.perf_counter()
        engine = Extractor(a.model, accept_cc_by_4=True)
        load = time.perf_counter()
        engine(pcm[: a.child * 16000])
        print(
            json.dumps(
                {
                    "load_ms": (load - start) * 1000,
                    "total_ms": (time.perf_counter() - start) * 1000,
                    "peak_rss_mib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
                    / 1024,
                }
            )
        )
        return
    result = {
        "host": platform.node(),
        "platform": platform.platform(),
        "threads": 1,
        "repeats": a.repeats,
        "load_average": os.getloadavg(),
        "cpu": Path("/proc/cpuinfo")
        .read_text()
        .split("model name")[1]
        .split("\n")[0]
        .split(":")[1]
        .strip(),
        "model_sha256": hashlib.sha256(a.model.read_bytes()).hexdigest(),
        "archive_sha256": hashlib.file_digest(
            a.archive.open("rb"), "sha256"
        ).hexdigest(),
        "fixtures": {k: [x[0] for x in v] for k, v in f.items()},
        "buckets": {},
    }
    engine = Extractor(a.model, accept_cc_by_4=True)
    for seconds in (1, 2, 3, 5):
        cold = []
        for _ in range(a.repeats):
            command = [
                sys.executable,
                __file__,
                "--model",
                str(a.model),
                "--archive",
                str(a.archive),
                "--child",
                str(seconds),
            ]
            start = time.perf_counter()
            sample = json.loads(subprocess.check_output(command))
            sample["process_ms"] = (time.perf_counter() - start) * 1000
            cold.append(sample)
        engine(pcm[: seconds * 16000])
        warm = []
        for _ in range(a.repeats):
            start = time.perf_counter()
            engine(pcm[: seconds * 16000])
            warm.append((time.perf_counter() - start) * 1000)
        result["buckets"][seconds] = {
            "cold": cold,
            "warm_ms": warm,
            "warm_p50_ms": float(np.percentile(warm, 50)),
            "warm_p95_ms": float(np.percentile(warm, 95)),
            "cold_p50_ms": float(np.percentile([x["total_ms"] for x in cold], 50)),
            "cold_p95_ms": float(np.percentile([x["total_ms"] for x in cold], 95)),
            "peak_rss_mib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024,
        }
    enrolled = {k: engine(v[0][1][:80000]) for k, v in list(f.items())[:2]}
    result["held_out"] = []
    for k, v in f.items():
        e = engine(v[1][1][:80000])
        result["held_out"].append(
            {
                "fixture_speaker": k,
                "predicted": identify(e, enrolled),
                "cosine": {name: float(e @ ref) for name, ref in enrolled.items()},
            }
        )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
