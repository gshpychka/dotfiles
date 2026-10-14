# Disabled integration release handoff

Owner authorized publication 2026-10-14 09:27 Kyiv. This worker performs no activation. Parent serializes after broker probe cc42fff6 deployment; never activate concurrently.

Target: task-scoped speaker-ID commit on voice/speaker-id-poc-20261014. Cherry-pick it onto parent-owned current broker rollout checkout, preserving probe and other work. Do not reset main or replace its checkout with this older worktree base. Resolve conversation/live conflicts by retaining probe changes and the optional hooks.

Build only voice-broker via existing packages/voice-broker/default.nix callPackage wiring at the merged revision, and run its package checks. Speaker-ID module has no top-level Sherpa import: existing broker Nix dependencies stay unchanged. Production creates Conversation without speaker_id, so no engine, template loading, VAD, microphone inference, or identity labeling executes. No model download/runtime option is added.

Narrow rollout: use the parent verified broker-only release procedure to update the voice-broker executable/artifact only, followed by a voice-broker.service-only restart if required and owner-approved. Do NOT use a whole-host nixos-rebuild switch, restart/stop/control hosting Gateway, or change HA/other service units. If a truly broker-only path is unavailable, report that blocker instead of broad activation. Capture resulting executable store path, broker service state, config identity with recording disabled, and existing probe proof. This worker deliberately does not supply invented deployment commands.

Deploying code with injection absent is not enabling biometric inference. Engine activation, household recording/enrollment, automatic identity, or personal templates remain prohibited until individual consent, calibration, process isolation/watchdog, overlap/timestamp QA, packaging validation, and separate approval. Public benchmark reproducer remains an isolated venv/Nix-shell tool, not a running system service.
