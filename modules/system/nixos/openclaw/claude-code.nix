# Claude Code sessions the agent starts, steers and checks on through ACP
# (https://docs.openclaw.ai/tools/acp-agents), on the owner's personal Claude
# plan. Sessions run as the gateway user and run every tool without asking.
#
# Imperative, one-time: sign in to the personal Claude plan as the gateway
# user:
#   sudo -iu openclaw claude      # /login, then /exit
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  # Claude Code's agent id in acpx's registry
  agentId = "claude";
  # where sessions clone repositories
  reposDir = "${cfg.workspace}/claude";
in
{
  options.my.openclaw.claudeCode.enable = lib.mkEnableOption "Claude Code sessions for the agent";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # ACP is on unless set to false
        services.openclaw-gateway.config.acp.enabled = cfg.claudeCode.enable;
      }
      (lib.mkIf cfg.claudeCode.enable {
        services.openclaw-gateway = {
          config = {
            acp = {
              backend = "acpx";
              defaultAgent = agentId;
              allowedAgents = [ agentId ];
            };
            plugins.entries.acpx = {
              enabled = true;
              # ACP sessions have no terminal to answer permission prompts on
              config.permissionMode = "approve-all";
            };
          };
          # the Claude ACP adapter's own `claude` is a binary for generic Linux, which NixOS cannot run
          environment.CLAUDE_CODE_EXECUTABLE = lib.getExe pkgs.claude-code;
        };

        my.openclaw = {
          extraPackages = [
            pkgs.jq
            pkgs.curl
            # for nix builds in sessions
            config.nix.package
          ];
          skills.claude-code = {
            description = "Start, steer and check on Claude Code sessions for coding work in git repositories.";
            text = ''
              Hand coding work to Claude Code with `sessions_spawn`, `runtime:
              "acp"` and `agentId: "${agentId}"`. Steer a running session with
              `sessions_send`; `sessions_list` and `sessions_history` show where it
              is. A finished run is announced back to you; tell the owner what it
              did.

              Sessions run as you, with network access, on the owner's personal
              Claude plan. Always pass `cwd`, since a session without one starts in
              your own workspace: `${reposDir}` to have it clone the repository
              there, or the clone's directory, such as `${reposDir}/<repo>`, to
              continue in one that exists.
            '';
          };
        };

        # the daemon admits only listed users
        nix.settings.allowed-users = [ gw.user ];

        systemd.tmpfiles.rules = [
          # tmpfiles creates a missing parent of a rule's path as root
          "d ${cfg.workspace} 0700 ${gw.user} ${gw.group} - -"
          "d ${reposDir} 0700 ${gw.user} ${gw.group} - -"
        ];

        # for the sign-in, in the gateway user's login shell
        users.users.${gw.user}.packages = [ pkgs.claude-code ];
      })
    ]
  );
}
