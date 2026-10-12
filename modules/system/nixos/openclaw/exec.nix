# The agent's commands on this host: every session's tools run as the gateway
# user, across the whole filesystem, without approval.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;

  # host exec approvals, which the gateway keeps in its SQLite state, outside
  # openclaw.json; host exec follows the stricter of these and tools.exec
  approvalsFile = pkgs.writeText "openclaw-exec-approvals.json" (
    builtins.toJSON {
      version = 1;
      defaults = {
        security = "full";
        ask = "off";
        askFallback = "full";
      };
    }
  );
in
{
  options.my.openclaw.extraPackages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = "Packages on PATH for the agent's commands.";
  };

  config = lib.mkIf cfg.enable {
    services.openclaw-gateway = {
      config = {
        tools.exec = {
          host = "gateway";
          mode = "full";
          # the wrappers before the system's packages: both hold sudo, and only
          # the wrapper's is setuid
          pathPrepend = map (package: "${lib.getBin package}/bin") cfg.extraPackages ++ [
            config.security.wrapperDir
            # OpenClaw's login-shell PATH merge is best-effort
            "/run/current-system/sw/bin"
          ];
          applyPatch.workspaceOnly = false;
        };
        # `! <command>` in a chat runs on this host
        commands.bash = true;
      };
      # non-fatal: the gateway starts on the approvals it already holds
      execStartPre = [ "-${lib.getExe' gw.package "openclaw"} approvals set --file ${approvalsFile}" ];
    };
  };
}
