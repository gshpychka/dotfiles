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

Installed baseline: effective live package z76j1mi33p6abl2qwlmwaj0si47220n6 remains
pinned by zz-preserve-live-no-probe-082912a.conf and was NOT replaced. The narrow
optional advisory compatibility merge described below preserves its hooks in
the routing candidate; no sidecar is enabled. Live activation is a separate
operator step, not part of package testing.

## Copy/paste: non-activating owner checks

Use the sole checkout. Stop if it has uncommitted work; do not stash/reset someone
else's work. These commands build only the package, never switch NixOS or restart
a service. Repeat with shadow or decisions in place of classifier to inspect those
configurations; decisions remains account-blocked. No API calls are made here.

```sh
cd /var/lib/openclaw/workspace/dotfiles
git status --short
# Continue only if status is empty.
git switch test/voice-ha-classifier
nix build .#nixosConfigurations.hoard.pkgs.voice-broker --out-link /tmp/voice-ha-owner-package
/tmp/voice-ha-owner-package/bin/voice-broker-replay --limit 28
git switch main
git status --short --branch
```

The commands above are shell commands (run in
/var/lib/openclaw/workspace/dotfiles). Run the initial status there and proceed
only if empty. Branch switch does not select the replay router: **without config,
replay ALWAYS measures the offline naive baseline**, including on classifier,
shadow and decisions branches. It is a CLI/dataset smoke test, not a fresh model
accuracy comparison. See benchmark-results.json for the existing paid comparison.
Do not add --config/--allow-api during these free checks.

For the naive package-only comparison:

```sh
git switch test/voice-ha-naive
nix build .#nixosConfigurations.hoard.pkgs.voice-broker --out-link /tmp/voice-ha-owner-naive
git switch main
```

That earlier package has no replay entry point; the offline
baseline replay in the classifier package above measures the same naive router.
After any failed build/replay, return to main manually (do not reset/clean).

## Exact non-activating deployment handoff (2026-10-16)

Historical pre-compatibility code revision:
73022c76abfa0693386dd66b3eb9700e9e81d865. Its system closure below is historical
evidence ONLY, not the final advisory-compatible activation candidate.

- Historical built system: /nix/store/x4phpy2dplpqhvylj16b44lzfqm041jd-nixos-system-hoard-26.11.20261011.7fd4004
- Historical broker: /nix/store/hk704xw7qlpy1b415abn08xda2hn8bag-voice-broker-0.1.0
- Config: /nix/store/wzm2fvxajn5bf8bgxmc781y2pr0azc3k-voice-broker.json
- Candidate service user: voice-broker; existing systemd credentials remain
  openai-api-key, device-token, home-assistant-token, openclaw-secret and identity.
- Package build test evidence: /tmp/voice-ha-classifier-system-final-build.log,
  line 226: 119 passed in 6.97s. This is an actual package check, not a replay score.
- Independent read-only review: archived transcript
  /var/lib/openclaw/agents/main/sessions/d7a56319-641d-4603-aa32-5bdeccad4b3c.jsonl.deleted.2026-10-16T05-05-57.670Z.87e2cf39cfff493bbb6c0ab72f26b5c7.zst
  final message e67fdeff-16b8-451d-9e36-4d503d58f750, 05:05:45 UTC:
  "Signoff: no remaining implementation blockers found in the reviewed integration."
  Review preceded the final replay CLI and request-budget/sampling changes; it is
  not a separate review of those later changes. Final 119 tests cover them.
- Full hoard build succeeded. All-systems flake evaluation exited 137; its
  replacement was cancelled for memory safety. No full-flake pass is claimed.
  Gateway health subsequently recovered under native custodian supervision.

### Source / effective drop-in compatibility assessment

Read-only comparison against the pinned installed source found only two changed
Python files versus canonical main (conversation.py and live.py), plus the
optional speaker_id.py module. Installed __main__.py is identical to main and
constructs Conversation without speaker_id; normal production startup therefore
leaves the optional advisory sidecar OFF. No new identification work is needed
or authorized for this routing comparison.

The installed optional hooks are nevertheless real compatibility surface:
Conversation accepts speaker_id, rejects simultaneous recording, closes it on
exit, exposes a failure-tolerant snapshot, and feeds cleaned PCM **after** Live
streaming without awaiting inference. Live's legacy task builder appends an
advisory explicitly forbidden for authorization. The routing candidate now preserves
these hooks via narrow edits, not whole-file replacement. speaker_id.py is an
exact copy of the installed module (SHA256
c66374d84bda2656f98f77335c0697585f571a1df046df4ada93ad0a3aaec858). No new
identification, enrollment, configuration or dependencies were added. Cleanup
also isolates close failures and disables a failed tap before closing it.

Legacy consults retain the installed advisory wording. Routed OpenClaw receives
the note in a separate JSON speaker_advisory field, explicitly untrusted and
never identity proof/authorization. Latest user text/history stay unchanged.
Classifier payloads and HA intent input omit this metadata entirely. It cannot
select a route or authorize a device action. No advisory appears by default.

Effective live override remains:
/run/systemd/system/voice-broker.service.d/zz-preserve-live-no-probe-082912a.conf
It clears ExecStart and pins broker z76j1mi33p6abl2qwlmwaj0si47220n6 with config
/nix/store/2psfk1gha2zrgykyw8qclgjzzr0fzhky-voice-broker.json.
A normal package build never changes it; a system build/activation alone must
not be assumed to replace that effective ExecStart. Preserve this file and the
old package/config as rollback evidence. This lane has not edited either.

**Ready now:** package/offline comparison and an advisory-compatible candidate
for separately authorized owner voice testing. Compatibility is no longer an
implementation blocker; the sidecar remains OFF and the live service unchanged.

Before any later authorized activation, preserve the effective override and
old broker/config verbatim for rollback. Explicitly reconcile only voice-broker's
ExecStart against the final package/config below; do not assume NixOS activation
will supersede the /run override. Do not copy whole conversation/live files over
each other, blindly remove the drop-in, or restart the Gateway. This document
performs no activation and supplies no automatic deploy command.

The prior hoard system build is scoped to the pre-compatibility code. Final
compatibility verification is package build/tests only; no heavy full-system or
full-flake rebuild was rerun. No provider benchmark was repeated.

### Final advisory-compatible package evidence

- Source: classifier code revision 5ec47f9 (common preservation commit 0897f09).
- Package: /nix/store/pjf8mhpi2z3kvys02hf0zn6727398l42-voice-broker-0.1.0
- Entry point: /nix/store/pjf8mhpi2z3kvys02hf0zn6727398l42-voice-broker-0.1.0/bin/voice-broker
- Existing classifier config (unchanged): /nix/store/wzm2fvxajn5bf8bgxmc781y2pr0azc3k-voice-broker.json
- Test log: /tmp/voice-ha-advisory-classifier-final-build.log:212,
  **126 passed in 7.23s**, including seven focused compatibility regressions and
  classifier metadata-exclusion regression in the existing factory test.
- Installed final package offline replay: 28 cases, 16/28 naive policy labels,
  two inappropriate HA routes; no backend/API calls. Not a new model benchmark.

Rollback must restore the original effective ExecStart pair, not the historical
system closure above: old broker z76j1mi33p6abl2qwlmwaj0si47220n6 and old config
2psfk1gha2zrgykyw8qclgjzzr0fzhky, preserving all other service settings/credentials.
The final compatible package is built, **not activated**.

Final independent read-only QA signed off code 5ec47f9 with no actionable
blockers, including compatibility, replay CLI/factory and final chat request
budget. Evidence: /var/lib/openclaw/workspace/tmp/voice-ha-final-qa-20261016.md.
Chat alone uses temperature=0/max_completion_tokens=32/store=false; do not infer
those request controls apply to Responses, Decisions or Jev adapters.
