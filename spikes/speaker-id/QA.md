# Independent release QA — 2026-10-14

Independent read-only review (run 5912c8b5-af46-4801-93ac-2a45967da10d) passes disabled POC release: no release-blocking defect found. Reviewer independently ran 51 tests (50 broker + one real public-fixture test), verified both model hashes, identical upstream/Sherpa ONNX graph, public archive checksum, clean diff, bounded buffering/job count, Live-first audio tap, disabled production default, no runtime persistence, recording-injection guard, and separate engine/weight licenses.

Before activation: require native process isolation/watchdog, real overlap/frame-loss signaling, timestamp mapping, household consent/calibration, in-memory revocation, and guarding optional close exceptions in teardown/feed-failure paths. These are explicitly not approval to enable inference. Nix shell warns about missing interactive <nixpkgs>, then runs checks successfully using environment bash.

Publication authorized by parent relaying owner 09:27 request. Deployment remains parent-serialized and disabled-only; this worker performs no activation.

## Probe-preserving merge QA

Independent read-only merge review cf8ec645-e4ac-4a22-b2c0-9c87a458836c passed content against origin/main90f2c37: playback probe implementation/tests byte-identical, current Turn/recall/delegation/startup improvements retained, expected speaker-only delta and additive ignores. Reviewer staging gate resolved by staging the current five-argument test constructor and merged test evidence. Local merged suite:79 passed (78 broker + one public fixture). Nix broker package checks:78 passed on Python3.14.7; build succeeded. Unrelated upstream patch whitespace is inherited unchanged; task-scoped diff against origin/main is clean.
