# Provider lane handoff — 2026-10-16

No shared checkout/index/branch changes. Core worker should copy classifier.py to
packages/voice-broker/src/voice_broker/classifier.py and test_classifier.py to
packages/voice-broker/tests/test_classifier.py. replay.py is optional standalone
shadow tooling/dataset, not a runtime dependency. run_offline.py is lane-only.

Contract: async router.route(RouteRequest) -> RouteDecision(route, elapsed_ms).
RouteRequest is the core frozen dataclass; Turn is the existing (role, text) tuple.
Optional async classify(request) -> Classification(route, elapsed_ms, confidence,
error). No shared mutable last result. Error contains exception TYPE only.
Timeout/refusal/malformed/low confidence yields clarify, never HA. Cancellation
propagates. Clarify MUST mean no actuator invocation in the outer controller.

Construct with an existing pooled async client:

    transport = httpx_transport(client, "https://api.openai.com/v1", token)
    router = OpenAIDecisionsRouter(transport, timeout_s=1.5)

Jev: base https://api.typesafe.ai/v1, JevRouter(transport), model jev-latest.
Other OpenAI-compatible: explicit base URL and model, OpenAICompatibleRouter(
transport, model="configured-model", api="chat" or "responses"). Strict JSON
schema defaults on; opt out explicitly for incompatible endpoints. Transport
calls paths relative to /v1. Existing broker httpx2 async client pattern is used;
no new library required. Owner manages client lifecycle. Disable retries on the
client. This transport disables redirects; bearer requires HTTPS. Thresholds are
not calibrated: min_confidence=0 by default, missing confidence fails closed if
a positive threshold is requested. Chat/Responses generate no confidence field.

Only last 12 context turns, text, area, device sent; conversation_id omitted.
No transcripts, prompts, response/error bodies or credentials logged. HTTP
observability on the injected client must likewise avoid sensitive body/header
logging. Classification is NOT authorization or entity resolution; HA backend
must retain its existing permissions and safety/clarification behavior.

## Verified official protocol sources

- https://developers.openai.com/api/docs/guides/decisions — public beta,
  POST /v1/decisions, model gpt-6-luna; input evidence + questions array;
  choice request uses choices array of value/description; answers array echoes
  name, has type choice, choice, probabilities array, confidence. Refusal exists.
  SDK Python >=3.26.0, so raw injected HTTP avoids requiring installed SDK update.
- https://developers.openai.com/api/docs/guides/structured-outputs — Chat
  response_format.json_schema and Responses text.format.json_schema.
- https://typesafe.ai/ — confirms TypeSafe's first System One model is Jev.
- https://docs.typesafe.ai/api.md — POST https://api.typesafe.ai/v1/systemone,
  Bearer token, model jev-latest, state object, questions MAP with choice criteria
  MAP, answers MAP with choice/confidence. Implemented concrete JevRouter only
  after this verification. Very high identification confidence; exact user
  intended vendor still unconfirmed. No invented Jev endpoint.
- https://docs.typesafe.ai/demos/smart-home.md — official relevant use-case page
  listed in their documentation index (not evaluated here).

OpenAI's “about 10x faster” and TypeSafe speed/cost claims are vendor advertising,
NOT measurements from this deployment. No live model accuracy/latency claims.

Existing-solutions preflight: official SDKs already cover providers; reuse existing
HTTP pool to avoid SDK version churn and heavyweight routing framework. Public
https://github.com/BerriAI/litellm and
https://github.com/aurelio-labs/semantic-router are viable larger maintained
routing/gateway candidates but unnecessary for this small closed-label interface.
web_search unavailable; used official docs and GitHub repository search via fetch.

## Offline verification

15 unittest cases passed against the actual core routing.py, no source writes.
run_offline.py stubs only unrelated openclaw.Turn import to avoid loading optional
OpenAI/httpx2 runtime dependencies. Tests cover all 3 provider adapters, both
OpenAI-compatible APIs, official request shapes, bounded history, missing names,
duplicate answers, invalid routes/confidence, threshold, malformed/refused/
incomplete responses, timeout/cancellation, redaction, no retries, pooled transport.

28 synthetic English/Ukrainian policy-labeled cases in replay.py. Baseline naive
accuracy 16/28 (57.14%), unsafe HA classifications 2/28; p50 0.0137 ms,
p95 0.0281 ms in one cold small run. Timings are CPU routing only, include no
network/HA execution; not statistically robust or comparable to live providers.
Dataset covers area defaults, scenes vs scene knowledge, weather vs weather
device, mixed coding+home tasks, context-dependent and context-free followups.
Do not mistake fixture/mock contract accuracy for a provider's real accuracy.

Reproduce from lane directory:

    PYTHONDONTWRITEBYTECODE=1 /nix/store/3gzjs8czrk47y7cpmr44jc568vqpb2p5-python3-3.13.15/bin/python3 run_offline.py
    PYTHONDONTWRITEBYTECODE=1 /nix/store/3gzjs8czrk47y7cpmr44jc568vqpb2p5-python3-3.13.15/bin/python3 run_offline.py replay.py

## Revision after initial core handoff

Core writer: RECOPY classifier.py and test_classifier.py from lane artifacts.
Added duplicate JSON-key rejection and rejection of Chat tool/function calls or
Responses actionable output items even alongside valid route text. New injection
regression test passes. No runtime contract changes. Initial live benchmark
loaded classifier before this parsing-only hardening; valid official strict-schema
route results use the identical prompt/contract. No extra inference calls for
hardening. Cancellation, refusal and confidence handling rechecked offline.

benchmark_live.py uses 28 cases x at most 2 documented small non-reasoning models,
56 inference calls max, estimated USD .10 cap and 32 generated-token cap per
request. Single GET models availability check; denies stop each model, no retries.
JSON output records aggregate usage plus only synthetic case IDs/labels/timings,
not prompts, transcripts or secrets. Output artifact: live_benchmark_result.json.
Models/prices verified at:
https://developers.openai.com/api/docs/models/gpt-4.1-nano
https://developers.openai.com/api/docs/models/gpt-4.1-mini

## Live capability check

RESULT: one actual synthetic POST /v1/decisions returned HTTP 403, error type
invalid_request_error, no error code/usage; 840.45 ms wall-clock rejection time
(not inference latency). No retry or paid benchmark followed. Existing service
key read in memory only, not copied/printed. Zero successful inferences; exact
billing unavailable, no reported usage. See live_probe_result.json. This is
endpoint-specific evidence, not merely the earlier GET model denial.

probe_decisions.py makes exactly ONE synthetic POST /v1/decisions request using
existing runtime credential, prints only status, error code/type or synthetic
answer/usage, no credential/error body. Do not automatically rerun or benchmark
on denial. No Jev account/key configured in this lane. No subscription created,
no home/device actions or production/default config changes performed.

Final reviewed artifact hashes:
- classifier.py: db66f4741e7ecc5390784af3f34deded0d8eec41be6768d86c811d76b6b43c21
- test_classifier.py: af2684c45365e2cccf7459a861eed50e1afc93e9324b0f31fc5911cb164403eb

Final parser changes: HTTP envelope decoded from response.text with duplicate-key
rejection; Responses messages require assistant role + completed status and only
output_text content (refusal/unknown/nested tool content fails closed). Custom
transport implementations must also reject duplicate keys before returning a dict.
