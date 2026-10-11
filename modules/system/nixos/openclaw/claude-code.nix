# Claude Code sessions the agent starts, steers and checks on through ACP
# (https://docs.openclaw.ai/tools/acp-agents), on the owner's personal Claude
# plan. A finished session is announced back to the session that started it.
#
# Sessions run as their own user. The gateway's ACP adapter (bundled acpx)
# starts `claude` through CLAUDE_CODE_EXECUTABLE, which this module points at
# sudo: sudo drops the gateway's environment, so a session sees none of the
# gateway's tokens, its state directory or its age key. Inside that user a
# session runs every tool without asking (acpx approve-all), and the user is
# the boundary: it reaches the network, its own home, the nix daemon (whose
# builds go to the distributed builders) and the GitHub App if set
# (github.nix). The gateway unit's sandboxing applies too: it writes only to
# its home and to the gateway's private /tmp.
#
# Imperative, one-time: sign in to the personal Claude plan as that user, then
# restart the gateway so its ACP startup probe passes:
#   sudo -u openclaw-code openclaw-claude      # /login, then /exit
#   sudo systemctl restart openclaw-gateway
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw.claudeCode;
  gw = config.services.openclaw-gateway;
  inherit (cfg) user home;
  # sessions start here unless the agent passes a cwd
  workDir = "${home}/work";

  # Claude Code as the sessions' user, with their PATH. Also the command the
  # owner signs in with.
  session = pkgs.writeShellApplication {
    name = "openclaw-claude";
    text = ''
      export HOME=${home}
      export PATH=${lib.makeBinPath cfg.tools}:/run/current-system/sw/bin
      # the gateway user, in this user's group, reads session files; never ~/.claude
      umask 0027
      exec ${lib.getExe pkgs.claude-code} "$@"
    '';
  };

  # CLAUDE_CODE_EXECUTABLE for the gateway's ACP adapter. sudo keeps the
  # working directory and, of the environment, only what the adapter sets up
  # for the CLI (CLAUDE_*; see security.sudo below).
  executable = pkgs.writeShellScript "openclaw-claude-as-${user}" ''
    exec ${config.security.wrapperDir}/sudo -n -u ${user} -- ${lib.getExe session} "$@"
  '';
in
{
  options.my.openclaw.claudeCode = {
    enable = lib.mkEnableOption "Claude Code sessions for the OpenClaw agent";
    user = lib.mkOption {
      type = lib.types.str;
      default = "openclaw-code";
      readOnly = true;
      description = "The user Claude Code sessions run as.";
    };
    home = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/${user}";
      readOnly = true;
      description = "Home of the sessions' user, holding its Claude sign-in and the sessions' work.";
    };
    tools = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Packages first on the sessions' PATH, before the system's.";
    };
  };

  config = lib.mkIf config.my.openclaw.enable (
    lib.mkMerge [
      {
        services.openclaw-gateway.config.acp =
          if cfg.enable then
            {
              enabled = true;
              backend = "acpx";
              defaultAgent = "claude";
              allowedAgents = [ "claude" ];
            }
          else
            { enabled = false; };
      }
      (lib.mkIf cfg.enable {
        users = {
          groups.${user} = { };
          users.${user} = {
            isSystemUser = true;
            group = user;
            inherit home;
            createHome = true;
            # the gateway user, in this group, starts sessions in workDir
            homeMode = "750";
            # for `sudo -u openclaw-code -i`
            shell = pkgs.bashInteractive;
          };
          users.${gw.user}.extraGroups = [ user ];
        };

        systemd.tmpfiles.rules = [
          # the sign-in and session history; the gateway user stays out
          "d ${home}/.claude 0700 ${user} ${user} - -"
          # group-owned, so the gateway's adapter reads what sessions write
          "d ${workDir} 2750 ${user} ${user} - -"
        ];

        # the gateway user may start Claude Code as the sessions' user, and nothing else
        security.sudo = {
          extraRules = [
            {
              users = [ gw.user ];
              runAs = user;
              commands = [
                {
                  command = lib.getExe session;
                  options = [ "NOPASSWD" ];
                }
              ];
            }
          ];
          # what the Claude Agent SDK sets for the CLI (CLAUDE_CODE_ENTRYPOINT,
          # CLAUDE_AGENT_SDK_VERSION, ...); the gateway's own secrets don't match
          extraConfig = ''
            Defaults!${lib.getExe session} env_keep += "CLAUDE_*"
          '';
        };

        environment.systemPackages = [ session ];

        # nix builds in sessions; the daemon admits only listed users
        nix.settings.allowed-users = [ user ];

        my.openclaw.claudeCode.tools = with pkgs; [
          git
          ripgrep
          jq
          curl
        ];

        services.openclaw-gateway = {
          # The adapter bundled with acpx carries its own `claude`, a binary
          # for generic Linux that NixOS cannot run; it honours this variable.
          environment.CLAUDE_CODE_EXECUTABLE = "${executable}";
          config.plugins.entries.acpx = {
            enabled = true;
            config = {
              # a failed startup probe leaves ACP unusable until a restart
              probeAgent = "claude";
              # Sessions the agent starts without a cwd: OpenClaw tries
              # <workspace>/claude first, which doesn't exist (and the sessions'
              # user couldn't enter), then falls back to this.
              cwd = workDir;
              # no one is at a terminal to approve tools; the user is the boundary
              permissionMode = "approve-all";
            };
          };
        };

        systemd.services.${gw.unitName}.serviceConfig.ReadWritePaths = [ home ];

        my.openclaw.skills.claude-code = {
          description = "Start, steer and check on Claude Code sessions for coding work in git repositories.";
          text = ''
            Hand coding work to Claude Code with `sessions_spawn`, `runtime:
            "acp"` and `agentId: "claude"`. Steer a running session with
            `sessions_send`; `sessions_list` and `sessions_history` show where it
            is. A finished run is announced back to you; tell the owner what it
            did.

            Sessions run as a separate user with network access, on the owner's
            personal Claude plan. Without a `cwd` they start in `${workDir}`:
            have them clone the repository there. To continue in a clone that
            exists, pass its directory, such as `${workDir}/<repo>`, as `cwd`.
            They cannot read your workspace, so put what they need in the task.
            ${lib.optionalString (config.my.openclaw.github != null) ''
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
