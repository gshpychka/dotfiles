# Claude Code sessions the agent starts, steers and checks on through ACP
# (https://docs.openclaw.ai/tools/acp-agents), on the owner's personal Claude
# plan. Sessions run as the gateway user and run every tool without asking.
#
# Imperative, one-time: sign in to the personal Claude plan as the gateway
# user, then restart the gateway so its ACP startup probe passes:
#   sudo -iu openclaw claude      # /login, then /exit
#   sudo systemctl restart openclaw-gateway
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  # the sessions' default working directory
  workDir = "${cfg.workspace}/claude";
in
{
  options.my.openclaw.claudeCode.enable =
    lib.mkEnableOption "Claude Code sessions for the OpenClaw agent";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.openclaw-gateway.config.acp =
          if cfg.claudeCode.enable then
            {
              enabled = true;
              backend = "acpx";
              defaultAgent = "claude";
              allowedAgents = [ "claude" ];
            }
          else
            { enabled = false; };
      }
      (lib.mkIf cfg.claudeCode.enable {
        # for the sign-in, in the gateway user's login shell
        users.users.${gw.user}.packages = [ pkgs.claude-code ];

        systemd.tmpfiles.rules = [ "d ${workDir} 0700 ${gw.user} ${gw.group} - -" ];

        # nix builds in sessions; the daemon admits only listed users
        nix.settings.allowed-users = [ gw.user ];

        my.openclaw.hostTools = with pkgs; [
          ripgrep
          jq
          curl
          config.nix.package
        ];

        services.openclaw-gateway = {
          # sessions inherit the gateway's PATH
          servicePath = cfg.hostTools;
          config.agents.entries.claude.runtime = {
            type = "acp";
            acp = {
              agent = "claude";
              backend = "acpx";
            };
          };
          # The adapter bundled with acpx carries its own `claude`, a binary
          # for generic Linux that NixOS cannot run; it honours this variable.
          environment.CLAUDE_CODE_EXECUTABLE = lib.getExe pkgs.claude-code;
          config.plugins.entries.acpx = {
            enabled = true;
            config = {
              # the agent whose startup probe gates the whole ACP backend
              probeAgent = "claude";
              # cwd of sessions started without one
              cwd = workDir;
              # sessions run unattended
              permissionMode = "approve-all";
            };
          };
        };

        my.openclaw.skills.claude-code = {
          description = "Start, steer and check on Claude Code sessions for coding work in git repositories.";
          text = ''
            Hand coding work to Claude Code with `sessions_spawn`, `runtime:
            "acp"` and `agentId: "claude"`. Steer a running session with
            `sessions_send`; `sessions_list` and `sessions_history` show where it
            is. A finished run is announced back to you; tell the owner what it
            did.

            Sessions run as you, with network access, on the owner's personal
            Claude plan. Without a `cwd` they start in `${workDir}`: have them
            clone the repository there. To continue in a clone that exists, pass
            its directory, such as `${workDir}/<repo>`, as `cwd`.
            ${lib.optionalString (cfg.github != null) ''
              They push and open pull requests as the agent's GitHub App, like
              your own git and `gh`.
            ''}
            Nix builds they run go to the build servers configured for this
            host when those are online.
          '';
        };
      })
    ]
  );
}
