# Local speaker ID POC — OFF, not deployed

Verdict: PARTIAL. Supported sherpa-onnx WeSpeaker engine, pinned weights,
public-fixture CPU evidence and staged advisory integration. Not household
accuracy validation. Owner authorized task-scoped commit/push after QA on
2026-10-14. No activation, restart, private recordings, new recordings, real
enrollment, training, or API spend occurred in this implementation run.

## Provenance and licensing

See provenance.json and retained WEIGHTS-MODEL-CARD.md. WeSpeaker's official
ResNet34 LM weights are **CC-BY-4.0**, not Apache. Attribute WeSpeaker /
wenet-e2e, retain source link and license, describe metadata-only adaptation.
Sherpa engine is separately Apache-2.0 (ENGINE-LICENSE). Pinned official HF
revision f0c48c298fd835726c27956a5d617bad7115627e exports the same ONNX graph:
verify_provenance.py confirms graph bytes and opsets match the Sherpa release.
Sherpa adds framework/sample-rate/output-dimension/scaling metadata only.
No custom conversion, guessed model family, or training.

Fixtures are LibriSpeech dev-clean, OpenSLR12, explicitly CC-BY-4.0; attribution:
Vassil Panayotov, Guoguo Chen, Daniel Povey, Sanjeev Khudanpur and LibriVox
readers. Source https://www.openslr.org/12/ . Clips are cropped in memory only;
no audio or embeddings redistributed. Archive hash and exact selected paths
are in benchmark-hoard.json. Public test references exist only in process RAM.

## Reproduce from repo root

Use Python 3.13 on x86_64 Linux; requirements.lock pins the tested dependencies.
On NixOS, enter the isolated shell (no system switch):

Commands:

~~~sh
nix-shell --impure spikes/speaker-id/shell.nix
python3 -m venv .speaker-id-cache/venv
.speaker-id-cache/venv/bin/pip install -r spikes/speaker-id/requirements.lock
export PYTHONPATH=$PWD/packages/voice-broker/src
curl -fL https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx -o .speaker-id-cache/model.onnx
curl -fL https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34-LM/resolve/f0c48c298fd835726c27956a5d617bad7115627e/voxceleb_resnet34_LM.onnx -o .speaker-id-cache/upstream.onnx
curl -fL https://www.openslr.org/resources/12/dev-clean.tar.gz -o .speaker-id-cache/dev-clean.tar.gz
.speaker-id-cache/venv/bin/python spikes/speaker-id/verify_provenance.py
.speaker-id-cache/venv/bin/python spikes/speaker-id/verify_fixture.py
(cd packages/voice-broker && ../../.speaker-id-cache/venv/bin/python setup.py build_ext --inplace)
.speaker-id-cache/venv/bin/pytest -q packages/voice-broker/tests
.speaker-id-cache/venv/bin/python spikes/speaker-id/benchmark.py --model .speaker-id-cache/model.onnx --archive .speaker-id-cache/dev-clean.tar.gz --repeats 20 > spikes/speaker-id/benchmark-hoard.json
.speaker-id-cache/venv/bin/pytest -q spikes/speaker-id/test_public.py
~~~

Nix shell was instantiated and used to build existing native AEC locally.
No production Nix dependency/package option changed. Standalone Sherpa wheel
packaging is deferred: pinning/patchelf of both core and binding wheels needs
independent packaging QA; shell + pinned isolated venv is the verified route.

## Privacy, enrollment, deletion

Runtime sidecar writes no audio, vectors, or logs. Buffer <=5 seconds, one
native inference, zero pending audio jobs. Default constructor enabled=False;
no config/env switch instantiates it. Model must be explicitly supplied and
weight-license acknowledgment supplied. No downloads at runtime.

Future enrollment requires each person's informed opt-in to local biometric
storage, intended personalization use, duration, access, deletion/revocation.
Never debug recordings, guessed enrollment, automatic template updates, or
voice authentication. Templates require private 0700 directory and 0600 files,
no symlink files, safe labels, pinned model identity; overwrite is refused.
Embeddings are sensitive, not anonymized. Filesystem deletion is not secure
erasure of SSD snapshots/backups; exclude templates from backup/sync.

Offline CLI (do not run on household audio without separate consent approval):

~~~sh
# Existing individually consented 16kHz mono files only; this never records.
.speaker-id-cache/venv/bin/python spikes/speaker-id/enrollment.py enroll --directory /private/templates --label person --model .speaker-id-cache/model.onnx --consent-local-biometric-template --accept-cc-by-4 /consented/audio.wav
.speaker-id-cache/venv/bin/python spikes/speaker-id/enrollment.py delete --directory /private/templates --label person
~~~

Deletion revokes the file; rebuild/drop running sidecar's in-memory reference
snapshot immediately when integrating revocation. No such runtime activation
exists today. Public benchmark never uses Templates/enrollment persistence.

## Staged audio integration and limitations

Conversation accepts an explicit injected sidecar; default None. Injection
refuses any nonempty recordings_dir (existing recorder must be disabled). Cleaned
16kHz PCM16 10ms AEC audio reaches Live first, then synchronous bounded VAD tap,
never await inference. One thread/CPU inference. Results carry utterance ID
and 16kHz sample range. Live snapshots already available result before consult;
unknown/pending are normal, no delegation wait. This is an advisory time range,
NOT exact transcript attribution: Live fragments lack acoustic timestamps.
Previous speaker invalidates at new voiced segment; old/late results discarded.

Cosine >=0.65 and second-best separation >=0.15 are uncalibrated POC settings,
NOT confidence probabilities. Too short (<1s), overlap suspicion, malformed
frame, overload, inference error, or deadline returns unknown/no advisory.
Energy VAD is deliberately modest: RMS 200, 300ms silence, max5s. It cannot
reliably distinguish noise or multiple speakers. Assistant playback marks
segment suspect; true human overlap requires an independent detector or
explicit upstream flag. Do not activate without validating that missing
capability, frame-loss signaling, and turn timestamp mapping.

Thread deadlines discard results; they **do not kill** native inference.
A stuck engine retains its sole worker and future jobs fail open to unknown.
ThreadPoolExecutor cannot guarantee hard shutdown on native hangs; a bounded
separate process with watchdog is required before production deployment.
Clean-room read English fixtures do not establish Ukrainian, far-field,
TV/echo/noise, illness/whisper, spoof/replay, or household discrimination.

## Authorized release versus household activation

Owner authorized QA, task-scoped push, then deployment of the disabled POC on 2026-10-14 at 09:27 Kyiv. This is not consent to household enrollment or automatic identification. Coordinate any broker deployment with the parent-owned playback-probe release; never switch an older isolated system checkout.

1. Independent QA of this worktree, privacy and license checks.
2. Package pinned Sherpa binding/core + model in Nix; prove build/import and
   attribution. Keep option disabled; no activation implicit in review.
3. Individually obtain informed enrollment consent and agreed deletion policy;
   disjoint held-out household evaluation, unknown-speaker false accepts and
   second-best margin calibration across rooms/languages/echo/overlap/spoofing.
4. Replace energy-only VAD/overlap suspicion with validated signaling; add exact
   turn/audio timestamps, frame-drop invalidation, isolated-process watchdog,
   per-conversation resource policy, revocation clearing in-memory refs.
5. Prove unchanged continuous audio under representative contention and stuck
   inference. Disabled POC release/deployment is already approved; household identity activation remains gated by consent, calibration and the engineering checks above. Proposed
   tap remains after AEC before resampling; no Gateway/HA restart required or
   needed for this POC. Speaker label never authorizes sensitive actions.
6. Only then a small supervised opt-in trial; rollback by removing injection.

### Timing methodology

benchmark-hoard.json retains every sample (20 cold fresh engine processes and
20 warm calls per 1/2/3/5s bucket), numpy linear percentile p50/p95. Cold total
starts before checksum+Sherpa import+model construction and ends after first
embedding; warm is extractor call only. Audio decode occurs before engine timer.
Process wall time also retained but includes repeated fixture archive scanning
and interpreter startup, so is not sidecar inference latency. No OS cache flush:
“cold” means fresh process/model, not physical disk-cache cold. Peak RSS from
getrusage is process high-water, not model-only or current service cgroup RSS.
Archive hashing streams rather than reading 322MiB into RAM. Parent peak
includes fixture parsing and model; child peak includes interpreter, fixtures,
model and first inference. Initial full-read hash contaminated inherited child
high-water RSS; that run was rejected and repeated with streaming hash. Durations are fixed first N seconds of public
read speech, can contain pauses, not certified N seconds of voiced frames.
These are current hoard contention results, not an unloaded hardware guarantee.

## Measured hoard results (2026-10-14)

Intel N100, one inference thread, 20 fresh processes + 20 warm calls per bucket.
Milliseconds below are p50 / p95, measured after audio decode; RSS is peak MiB.

- 1s: warm 180.1 / 207.9 ms; cold 457.5 / 537.3 ms; child RSS 131.9 / 135.4 MiB.
- 2s: warm 275.6 / 284.9 ms; cold 523.8 / 559.6 ms; child RSS 133.3 / 136.0 MiB.
- 3s: warm 413.1 / 490.0 ms; cold 592.5 / 675.4 ms; child RSS 135.3 / 143.5 MiB.
- 5s: warm 860.3 / 1129.9 ms; cold 1150.1 / 1543.1 ms; child RSS 149.3 / 156.2 MiB.

Default 750ms advisory deadline can expire on 5s inference; generic unknown behavior is intentional, never delay Live/delegation.
Disjoint public 5s held-out clips: both enrolled fixture speakers matched (cosines 0.839 and 0.823); third speaker unknown (best cosine 0.416). Only three clean read-English examples, not a household accuracy estimate.
Verification: 50 broker tests passed; one real-public-fixture integration test passed; Ruff and git diff --check clean. Native AEC extension built locally in Nix shell, shell instantiated. Independent release QA precedes publication; operational activation is serialized by the parent.
