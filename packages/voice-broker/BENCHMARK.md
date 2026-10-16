# Actual bounded classifier benchmark — 2026-10-16

Existing OpenAI service key used in memory only. No secrets/private history logged,
no actuators/tools invoked. 56 inference calls (28 per model), all HTTP 200 and
valid route outputs, zero failed inference calls. One additional GET /v1/models
returned 403; this did NOT imply Chat inference denial. Models selected from
verified official model documentation. Earlier Decisions POST remains 403 and
was NOT retried. Jev has no configured credential in this lane.

## Measured results

| Model | Accuracy | Inappropriate HA | p50 | p95 | Input/output tokens | Estimated USD |
|---|---:|---:|---:|---:|---:|---:|
| gpt-4.1-nano | 17/28 = 60.71% | 6/28 | 586.04 ms | 1097.85 ms | 7355 / 161 | .0007999 |
| gpt-4.1-mini | 27/28 = 96.43% | 0/28 | 656.59 ms | 791.36 ms | 7355 / 165 | .0032060 |

Total 14,710 input + 326 output tokens, no cached tokens; estimated total
USD .0040059 from documented token prices, NOT a billing statement. USD .10 cap,
32 max generated tokens per call, no retries. Chat Completions strict schema,
temperature 0, store false. Pricing:
https://developers.openai.com/api/docs/models/gpt-4.1-nano
https://developers.openai.com/api/docs/models/gpt-4.1-mini

Confusion (expected -> observed):

- Nano: ha->ha 10; ha->clarify 2; openclaw->openclaw 7;
  clarify->ha 4; clarify->openclaw 2; openclaw->ha 2; openclaw->clarify 1.
- Mini: ha->ha 12; openclaw->openclaw 9; clarify->clarify 6;
  openclaw->clarify 1. Only mismatch is uk-mixed, which safely clarified rather
  than routing the mixed home+coding task to OpenClaw.

Nano sent context-free ambiguous/incomplete utterances to HA (4 cases) and both
mixed home+coding utterances to HA (2 cases). Do not recommend nano as the default
from this evidence. Mini is the better next final-test candidate, not proven safe
by this small sample. No production default was changed.

## Important caveats

28 synthetic bilingual policy-labeled examples, single pass, not held-out or
representative household traffic. No confidence interval or provider calibration.
Zero inappropriate HA observed for mini is not a guarantee. Classifier still
requires permission-preserving downstream HA interpretation/clarification.

Timing is full classify wall-clock including actual HTTP, connection/TLS setup,
and parsing; stdlib urllib opens fresh connections, not the pooled production
transport. Not a clean model-compute benchmark, concurrency/saturation test,
voice end-to-end benchmark or reliable tail-latency estimate. p95 is nearest-rank
27th of 28 samples. No artificial sleep included in per-request timings.

The live process loaded the classifier before parsing-only hardening was added;
prompt/schema and valid-output interpretation are unchanged. Current artifacts
reject duplicate JSON keys, Chat tool/function calls and Responses action items.
15 current offline tests pass. Independent safety review found 3 additional
parsing bypasses, all fixed with regressions: duplicate envelope keys, nested
unexpected Responses content, and incomplete/non-assistant output messages.

Full case IDs, routes, HTTP/routing durations, returned model snapshot and usage:
live_benchmark_result.json. Contains no text or credentials. Re-running
benchmark_live.py would make NEW billable calls; do not rerun automatically.

## Integration delta for core writer

RECOPY current classifier.py + test_classifier.py from the lane directory.
No Git mutations or tracked-source edits performed by this lane. Public Router
contract unchanged. Initial provider handoff versions predate hardening.

Final reviewed artifact hashes:
- classifier.py: db66f4741e7ecc5390784af3f34deded0d8eec41be6768d86c811d76b6b43c21
- test_classifier.py: af2684c45365e2cccf7459a861eed50e1afc93e9324b0f31fc5911cb164403eb

Final parser changes: HTTP envelope decoded from response.text with duplicate-key
rejection; Responses messages require assistant role + completed status and only
output_text content (refusal/unknown/nested tool content fails closed). Custom
transport implementations must also reject duplicate keys before returning a dict.
