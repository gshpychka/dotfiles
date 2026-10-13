# Shell commands on this host, from the agent's tools and from `! <command>` in
# a chat, without approval (https://docs.openclaw.ai/tools/exec-approvals).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;

  # host exec approvals (https://docs.openclaw.ai/tools/exec-approvals)
  approvalsFile = pkgs.writeText "openclaw-exec-approvals.json" (
    builtins.toJSON {
      # an approval prompt no one answers lets the command run
      defaults.askFallback = "full";
    }
  );
in
{
  options.my.openclaw.extraPackages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = "Packages on PATH for the commands the gateway runs on this host.";
  };

  config = lib.mkIf cfg.enable {
    services.openclaw-gateway = {
      config = {
        tools.exec = {
          host = "gateway";
          # ahead of the login shell's PATH, which OpenClaw puts before the unit's
          pathPrepend = map (package: "${lib.getBin package}/bin") cfg.extraPackages;
          applyPatch.workspaceOnly = false;
        };
        # `! <command>` in a chat, for the senders tools.elevated.allowFrom admits
        commands.bash = true;
      };
      # the approvals live in SQLite state outside openclaw.json, so each start replaces them
      # `-`: the gateway starts on the stored approvals when the replacement fails
      execStartPre = [ "-${lib.getExe gw.package} approvals set --file ${approvalsFile}" ];
    };

    # the unit's PATH, which `! <command>` and the agent's tools inherit
    systemd.services.${gw.unitName}.path = [
      # setuid sudo, ahead of the system packages' plain sudo
      "/run/wrappers"
    ]
    ++ cfg.extraPackages
    ++ [
      # the system's packages, at a path that outlives rebuilds
      "/run/current-system/sw"
    ];
  };
}
