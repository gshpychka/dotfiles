# NixOS control

One owner-only SDK contextVersion 2 tool:

    nixos_control({operation: "build" | "switch", revision: "<40 lowercase hex>"})

The host validates the schema; the unchanged nixos-switch controller validates
its arguments and canonical-main ancestry and builds remotely (--max-jobs 0).
The plugin checks live invocation authority immediately before execFile, using
argument arrays, not shell interpolation. Sandboxed/non-owner contexts get no tool.

A two-line immutable shell helper execs systemd-run with fixed unit/command/options
and forwards quoted arguments to nixos-switch. Its exact store path alone receives
NOPASSWD for hoard's openclaw identity; no arbitrary privileged shell or systemd
properties are exposed. The helper is necessary because nixos-switch detaches
activation but performs its preceding fetch/build in the caller's cgroup.
The whole controller runs in nixos-control.service, outside the Gateway cgroup;
its existing activation still uses nixos-switch.service. A running fixed-name unit
rejects overlapping submissions. No new deployment engine or policy bypass.

Submission is not completion. Inspect existing systemd/journal records:

    systemctl status nixos-control nixos-switch
    journalctl -u nixos-control -u nixos-switch --no-pager

Completed units are collected; the journal retains outcomes according to the host's
existing retention policy. There are no receipts, replay/idempotency store, outbox,
notification service, or custom status tool. On ambiguous admission, inspect the
journal before deciding whether to retry. No automatic replay.

The former nixos_control_status and requestId parameter are removed. Historical
/var/lib/nixos-control records are deliberately untouched (root can inspect them);
the old receipt runner is no longer created, and its completion service is removed.
Let any already admitted old operation finish before deploying this replacement.
Apply via the currently installed native control tool, never a shell restart of
the hosting Gateway. Existing plugin paths, policy and broker overrides are merged
unchanged. Controller drain/readiness/rollback behavior is unchanged.

Build-only verification (no activation):

    nix build .#nixosConfigurations.hoard.config.system.build.nixosControl --max-jobs 0 --no-link --print-out-paths

This runs a small installed-SDK registration/caller/dispatch test with subprocess
effects mocked. Nix packages the SDK link and substitutes the exact helper path.
