# Claude Code sessions the agent starts, steers and checks on through ACP
# (https://docs.openclaw.ai/tools/acp-agents), on the owner's personal Claude
# plan.
#
# Sessions run as their own user, which is their boundary: it holds none of the
# gateway's environment, state directory or age key, and reaches the network,
# its own home and the nix daemon. Inside it a session runs every tool without
# asking.
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
  # the sessions' default working directory
  workDir = "${home}/work";
  outputChain = "openclaw-code-out";

  # Claude Code with the sessions' home and PATH.
  session = pkgs.writeShellApplication {
    name = "openclaw-claude";
    text = ''
      export HOME=${home}
      export PATH=${lib.makeBinPath cfg.tools}:/run/current-system/sw/bin
      # group-readable, for the gateway user in this user's group
      umask 0027
      exec ${lib.getExe pkgs.claude-code} "$@"
    '';
  };

  # Claude Code as the sessions' user, in the adapter's working directory.
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

        # The gateway's trusted-proxy auth admits any loopback connection naming
        # a proxied user, so sessions stay off its port; the ACP adapter
        # connects as the gateway user.
        networking.firewall.extraCommands = lib.mkIf (!config.networking.nftables.enable) ''
          for ipt in iptables ${lib.optionalString config.networking.enableIPv6 "ip6tables"}; do
            $ipt -w -N ${outputChain} 2>/dev/null || true
            $ipt -w -F ${outputChain}
            $ipt -w -A ${outputChain} -o lo -p tcp --dport ${toString gw.port} -j REJECT --reject-with tcp-reset
            $ipt -w -C OUTPUT -m owner --uid-owner ${user} -j ${outputChain} 2>/dev/null \
              || $ipt -w -A OUTPUT -m owner --uid-owner ${user} -j ${outputChain}
          done
        '';
        networking.nftables.tables.${outputChain} = lib.mkIf config.networking.nftables.enable {
          family = "inet";
          content = ''
            chain output {
              type filter hook output priority filter; policy accept;
              oif lo meta skuid "${user}" tcp dport ${toString gw.port} reject with tcp reset
            }
          '';
        };

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
              # the agent whose startup probe gates the whole ACP backend
              probeAgent = "claude";
              # cwd of sessions started without one; OpenClaw's own choice,
              # <workspace>/claude when it exists, is closed to the sessions'
              # user
              cwd = workDir;
              # sessions run unattended; the sessions' user is the boundary
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
