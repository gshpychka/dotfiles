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
Gateway's non-executing `chat.inject` protocol, after commentary is sent. Existing
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

## Final compatibility and safe owner checks

The installed optional advisory hooks are now preserved narrowly (common source
commit 0897f09), with sidecar injection default OFF. The installed speaker_id.py
is copied byte-for-byte, no new identity/voice/enrollment work. Advisory remains
untrusted, nonauthoritative OpenClaw metadata, not classifier/HA input. Audio goes
to Live before the optional queue-only tap; failures detach the sidecar and
cleanup errors cannot interrupt device close. No service or drop-in was changed.

Package-only baseline comparison (sole checkout; stop if initial status is not
empty; never reset/stash someone else's work):

```sh
cd /var/lib/openclaw/workspace/dotfiles
git status --short
# Continue only if empty.
git switch test/voice-ha-naive
nix build .#nixosConfigurations.hoard.pkgs.voice-broker --out-link /tmp/voice-ha-owner-naive
git switch main
git status --short --branch
```

The naive package has no replay CLI. For a free 28-case naive replay and the full
classifier/shadow/Decisions comparison handoff, use the commands in
https://github.com/gshpychka/realm/blob/test/voice-ha-classifier/packages/voice-broker/ROUTING.md
Default replay measures naive even on classifier branches; no provider calls
without explicit --config plus --allow-api. Do not repeat the paid benchmark.

Final independent source QA: /var/lib/openclaw/workspace/tmp/voice-ha-final-qa-20261016.md.
Full hoard system evidence predates compatibility; final verification uses package
build/tests only. Previous all-systems flake evaluation exited137, not a pass.
Keep the live zz-preserve-live-no-probe-082912a.conf override unchanged until a
separately authorized test activation; preserve its original package/config pair
for rollback. No Gateway restart or full-system activation is needed for checks.
