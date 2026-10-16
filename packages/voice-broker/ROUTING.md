# Client-delegation routing experiments

The existing GPT-Live client delegation remains the voice/audio transport.
This change adds an **opt-in** pre-execution broker router; absent `routing` keeps
production OpenClaw-only behavior. No runtime service or drop-in is changed by
building a branch. Do not deploy an experimental winner without comparing it.

## Common path

Completed-candidate transcript -> route -> exactly one of:
- HA: official WebSocket `assist_pipeline/run`, intent -> intent, preserving
  **Remote** pipeline `01jmq3hbakt5r0e136vd886hy9` (conversation.chatgpt,
  prefer_local_intents=true). HA speech text returns to Live commentary; HA TTS
  never runs. Existing HA service credential/user is reused.
- OpenClaw: existing Responses ingress and main session key, with full latest
  request, recent history, device/Room and unique voice conversation ID.
- Clarify: no backend executes. Classification failure also clarifies.

Neither Assist success nor its LLM is used as a HA/no-match classifier. No
fallback/retry follows timeout, disconnect, partial success or uncertain action.
Consumed requests are not replayed by a repeated delegation. Live speaks results
once; there is no second TTS path. HA retains its own conversation ID across
home turns. OpenClaw receives all session context on generic turns.

## Important experimental transcript limitation

Official Live has no final-user-transcript event. Deltas have approximate times;
delegation metadata is NOT a task prompt or destination. The broker waits for a
350 ms settled snapshot (bounded at 2 s), requires transcript timing no later
than the delegation offset and terminal punctuation, and checks for user
corrections again after classification, before a backend starts. Missing,
unfinished or uncorrelated speech asks for a repeat. A late fragment after the
settlement window cannot be proven absent; **this is not a guaranteed endpointing
protocol**. No partial transcript event directly triggers actions. Validate this
conservative tradeoff in final voice tests; punctuation-free STT clarifies.

## History and privacy

HA/clarification results are appended as already-handled context through the
Gateway's non-executing `chat.inject` protocol, after commentary is sent.
An atomic fsynced uncertain-execution record is staged before backend execution;
the result is durably staged before commentary, so disconnects cannot erase it. Existing
OpenClaw turns already persist normally and are not injected again. A private
0700/0600 outbox holds unacknowledged text/results and feeds recent context.
Uncertain injection is not automatically retried (no idempotency key). No audio
recording, enrollment, extra auth/user, MCP proxy, or transcript/result logging
is introduced. Review retained outbox records if Gateway history injection fails.
The outbox is backend history, not household audio, and obeys the existing
history age/character limits when recalled. Files await operator reconciliation
rather than silent deletion on uncertain delivery.

## Configuration (test branches only)

Add to broker JSON, or my.voice-broker.settings on a selected test branch:

    "routing": {
      "strategy": "naive",
      "pipeline": "01jmq3hbakt5r0e136vd886hy9",
      "devices": {
        "room-assistant": "e96b17992356c46e2324bcdb0325cf13",
        "kitchen-assistant": "1934b52923c293b268f3c9620e874156"
      },
      "settle_s": 0.35
    }

IDs were read from existing HA registry on 2026-10-16. Device Room defaults stay
in HA via device_id. Pipeline does not change the installed preferred pipeline.
Naive is intentionally vocabulary-based and has known false routes; it is a
comparison baseline, **not the recommended production classifier**.

## Measurement and verification

Logs contain bounded scalar route_ms, backend_ms, total_ms and first_reply_ms
(delegation to first non-silent audio received at broker). First audio can be a
Live acknowledgment, not verified task completion, and excludes hardware
playback latency. No latency improvement is claimed without live measurement.
Synthetic tests cover UA/EN scene/device/weather/coding/followups, delayed
transcript and delegation ordering, stale classification, duplicate delegation,
uncertain result, intent-only HA, conversation IDs and private history handoff.
Live checks are read-only; no device actions or room playback without a final
test request. Build the package with:

    nix build .#nixosConfigurations.hoard.pkgs.voice-broker

Sources: developers.openai.com/api/docs/guides/live-delegation and
live-conversations; developers.home-assistant.io/docs/voice/pipelines/;
docs.openclaw.ai/gateway/openresponses-http-api; Gateway protocol chat.inject
schema/handler. Existing official APIs and installed HTTP/WebSocket libraries
were adequate; no routing framework or new service was needed.

## Comparison directions and readiness

- `test/voice-ha-naive`: vocabulary baseline, no classifier API; known bad routes.
- `test/voice-ha-classifier`: pooled OpenAI-compatible gpt-4.1-mini classifier,
  same single HA/OpenClaw execution path; preferred candidate for final tests.
- `test/voice-ha-shadow`: same candidate observed, only OpenClaw executes; no
  duplicate HA action. Shadow still has classifier latency/cost and the same
  conservative transcript boundary gate.
- `test/voice-ha-decisions`: exact Decisions adapter test configuration; account
  POST /v1/decisions returned 403, so do not expect inference until access changes.

All branches reuse the existing checkout, not extra worktrees. Published refs
are test configurations, not a change to production or an instruction to deploy.
Jev was identified as TypeSafe System One (docs.typesafe.ai/api.md). Its concrete
adapter is available via classifier.provider=jev, base_url=https://api.typesafe.ai/v1,
model=jev-latest, and token_file pointing at an explicitly provisioned systemd
credential. No Jev credential/account was created. The existing OpenAI key is
never forwarded to another host. classifier.provider=decisions uses the
OpenAI base_url and model=gpt-6-luna. provider=compatible supports api=chat or
responses and an explicit model/base URL; there is no automatic model fallback.

`voice-broker-replay` runs the 28-case synthetic UA/EN dataset locally by default.
It never calls HA/OpenClaw or plays audio. To intentionally test a configured
provider, use `--config <broker.json> --allow-api --limit 28` (at most 28 calls).
Use existing credential references; do not put credentials on the command line.
See BENCHMARK.md and benchmark-results.json for the already-run 56 successful
synthetic API calls, token counts, costs and accuracy. Repeated benchmarks are
not automatic. Replay reports policy-label accuracy, inappropriate HA routes and
wall-clock p50/p95; it is not household audio or voice end-to-end measurement.

Read-only Remote Assist package verification (2026-10-16): English Room
temperature query 46.4 ms, Ukrainian query 4139.4 ms, both returned a numeric
reading and HA conversation ID with intent-only stages. No device changes or
speaker playback. Two samples are not latency percentiles. English likely took
local intents; Ukrainian may need the existing Remote LLM. No pipeline settings
were changed and backend results remain final-text delivery, not incremental
intent-progress speech.

Deployment caveat: effective live package z76j1mi33p6abl2qwlmwaj0si47220n6 has
conversation.py/live.py speaker-advisory changes absent from canonical main.
It remains pinned by zz-preserve-live-no-probe-082912a.conf and was NOT replaced.
Parent must explicitly reconcile that baseline before a final test activation;
do not treat a runtime override as canonical source or silently remove it.
