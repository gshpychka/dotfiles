# Native NixOS control for hoard

Installable native plugin and narrowly privileged receipt adapter for the existing
nixos-switch controller. No alternate deployment engine; no Gateway policy edits.

## Interface / safety boundary

* nixos_control: operation build|switch, full lowercase 40-hex revision, lowercase
  32-hex requestId. Same requestId/payload is idempotent; conflicting reuse refuses.
* nixos_control_status: requestId only. No arbitrary command, path, repository,
  host, environment or systemd properties can be supplied.
* Both tools use SDK contextVersion 2, require senderIsOwner, refuse sandboxed/
  unidentified callers, and recheck assertInvocationCurrent at fixed process
  admission. Tool names alone are not authorization. Detached jobs do not acquire
  an owner's identity, and owner continuations are accepted only by the SDK's live
  exact-parent authority. A process already admitted is owned work; later revocation
  does not replay/cancel accepted controller effects or discard durable state.
  The real SDK rechecks authority after asynchronous return: a revoked caller
  can receive an error even after job admission. The caller already knows the
  requestId and must query that same ID when authorized again, never manufacture
  a new ID to retry an unknown outcome. Build QA executes the installed SDK
  callback binder body under mocked lifecycle dependencies to prove this case.
* Root-owned immutable helper accepts only the configured openclaw Unix service
  identity via sudo. Its exact executable receives one narrowly scoped NOPASSWD
  rule, not blanket root or arbitrary shell. Existing unrelated sudo rules are
  preserved, not replaced. OS root and already-root-capable local operators remain
  trusted; this is not a sandbox against a compromised Gateway account.
* Native tool registration is the supported host-control route. Actual installation,
  config application, host bootstrap and deployment must be done through approved
  parent OpenClaw control/operator setup, NEVER agent exec to bypass the restriction.

## What executes

The adapter pins config.system.build.nixosSwitch's immutable executable. The
controller validates the commit on canonical GitHub main, builds its exact tree
and lock remotely, and switches using its existing nixos-switch.service. The
Gateway's existing service handles graceful drain/readiness; the existing
activation helper handles profile/runtime/boot rollback. None is reimplemented.

A single external nixos-control-receipt.service is only a receipt runner around
that fixed command. It keeps the build and result collection outside the Gateway
cgroup and returns admission promptly so this turn can finish before graceful drain.
A root-only flock serializes helper admission; active receipt runner OR existing
activation blocks another operation. The runner has a six-hour ceiling. If stopped
while activation is already in its independent existing unit, that activation can
continue: receipt is interrupted/unknown, never a claimed rollback or auto-replay.
Manual deployments outside this adapter are not made transaction-safe by it.

Root-owned receipts and logs under /var/lib/nixos-control use mode 0700/0600.
Intent is fsynced and atomically renamed before systemd dispatch; files and parent
are fsynced. Completion retains operation, SHA, origin session, times, exit/signal,
rollback evidence and acknowledgement. The same id never executes twice. Unknown
admission, missing runner after a reboot, or failed spawn retains an interrupted
receipt and does not automatically retry. Terminal failure alone does not prove
rollback; rollbackConfirmed requires the existing controller's explicit proof.
This does not rollback data migrations or make power loss during activation safe.

## Restart completion

A version-2 native plugin service uses the host-owned scheduler, reconciling root
outbox receipts on startup and every 15 seconds. It uses the documented native
channel outbound adapter to send a deterministic notice to the exact channel,
recipient, account and thread captured from the host's trusted deliveryContext at
owner tool admission. Route is not a model argument and replay cannot retarget it.
Missing host delivery context refuses job admission; missing/disabled adapters or
failed/suppressed sends leave the outbox pending. Service cancellation is checked
at final platform dispatch, including after asynchronous adapter preparation.
Only a matching channel and nonempty confirmed platform message ID acknowledges,
and that delivery receipt is durably recorded by the root helper. No model turn,
last-route inference, or retained owner's invocation grant is used for completion.

This deliberately does not use runHeartbeatOnce: inspecting the real candidate's
wake policy showed that the public wrapper cannot provide source/intent and can
skip with heartbeat.every=0m. Moreover, a ran/silent outcome is not send proof.
Completion does not enable periodic heartbeats or depend on their cadence.
Delivery remains at-least-once: a crash after a confirmed platform send but before
root acknowledgement can cause a duplicate notice with the same request ID.
A platform receipt proves accepted platform delivery, not that a human read it.
The owner can always query the durable receipt with nixos_control_status.

## Files / declarative integration

* index.mjs, openclaw.plugin.json, package.json: standard native plugin entry.
* core.mjs: narrow owner-v2 tool factory; transport.mjs: fixed execFile/sudo bridge.
* host.mjs: root receipt adapter around existing controller, not a switch engine.
* service.mjs: bounded host-scheduled restart reconciliation.
* *.test.mjs: mocked controller/systemd, real temporary-file receipt persistence.
* integration-check.mjs: imports the real installed SDK, mock-registers tools and
  service, verifies manifest ownership and denied owner contexts; no service starts.
* modules/system/nixos/openclaw/nixos-control.nix: builds immutable host helper/plugin,
  narrow sudo rule, root state directory, merged plugin load path and tools.alsoAllow.
* modules/system/nixos/nixos-switch.nix: exposes existing controller through
  system.build.nixosSwitch (its behavior is unchanged).
* machines/hoard/openclaw.nix: enables the source option nixosControl.enable.
* gateway.nix/codex.nix: aggregate plugin paths in typed my.openclaw.pluginPaths.
  The pinned upstream config type uses recursiveUpdate and replaces JSON lists;
  naïvely adding another load.paths silently drops it. The typed merge preserves
  Codex and the new plugin before rendering one final list. This was discovered
  by the real config-check warning and corrected, not hidden or ignored.

The raw source contains @...@ build placeholders and is NOT installed directly.
The built Nix output substitutes every privileged path and contains the actual
installable plugin under share/openclaw-plugin-nixos-control. Runtime imports use
its Nix-pinned OpenClaw SDK link; no npm dependency downloads or lifecycle scripts.

## Build / source QA (does not activate anything)

    node --test scripts/nixos-control/*.test.mjs
    nix build .#nixosConfigurations.hoard.config.system.build.nixosControl --no-link --print-out-paths

Build runs all tests and the installed-SDK registration check. Use the printed
package's share/openclaw-plugin-nixos-control directory as the plugin package.
It was built remotely on reaper with fifteen passing tests and real SDK smoke
check. Systemd/controller execution remains mocked: no actual build/switch,
privileged helper invocation, Gateway restart, plugin install or delivery occurred.

## Minimal approved bootstrap

The first host application must establish the exact immutable helper's sudo rule
and root state directory. A plugin-only install cannot grant root privilege, and
an uninstalled tool cannot bootstrap its own system permissions. Parent approved
OpenClaw host control should apply the declarative source changes. If that control
cannot apply host NixOS generations, an operator must do the one-time normal NixOS
application; this is a missing host setup capability, not a request for broader
user permission or a reason to rewrite system instructions.

Once helper privilege/state exists, documented native plugin operations are:

    openclaw plugins install <built-package>/share/openclaw-plugin-nixos-control
    openclaw plugins inspect nixos-control --runtime --json
    openclaw plugins reload nixos-control

These are for approved OpenClaw/operator setup, not this child's exec. On this
Nix-managed host prefer the declarative load.paths/entries configuration already
provided: preserve existing codex/acpx, all deny policy, and voice-broker overrides.
Use reload after source changes rather than a shell service restart. No command
for a nonexistent openclaw action has been invented.

Before live acceptance, inspect plugin runtime and effective catalog, verify
owner-only denial, confirm the exact helper/state ownership and sudo rule, then
use approved nixos_control build followed by the explicitly authorized switch.
Record the returned requestId and verify terminal receipt and actual routed
completion after the Gateway returns. Accepted/running is never completion.

## Grounded support evidence

Installed OpenClaw docs/plugins/building-plugins.md and tool-plugins.md document
native factories, v2 owner authority, optional tools, manifest contracts and plugin
installation/reload. sdk-runtime/channel.md documents outbound.loadAdapter;
the actual candidate SDK defines ChannelOutboundAdapter.sendText, deliveryContext
and final-dispatch cancellation/authorization guards. This is not the trust-gated
dispatchHookAgentTurn/Gateway scope elevation route, nor a custom Telegram HTTP
client. Local plugins do not magically become bundled/trusted-official:
inspect provenance and do not falsify a trust record or package metadata.
The installed official plugin inventory/catalog contains no NixOS switch tool;
admin-http-rpc adds Gateway RPC dispatch, not this operation. Web search was
unavailable, so community-plugin availability is not claimed to be exhausted.
The existing prohibition lives in installed dist/system-prompt-config-BH_-eIvU.mjs,
OpenClaw Control section. It has not been edited or weakened.
