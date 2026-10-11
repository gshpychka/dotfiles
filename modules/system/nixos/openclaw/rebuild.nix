# Lets the OpenClaw agent rebuild this host, always from the flake on GitHub
# and never from a checkout it can write to: what reaches root is what was
# merged there.
#
# The rebuild runs as its own unit, so it finishes even when the switch
# restarts the gateway, and the owner hears how it ended straight from the
# Telegram Bot API.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  unitName = "openclaw-rebuild";
  logFile = "/var/log/${unitName}.log";

  command = pkgs.writeShellApplication {
    name = unitName;
    runtimeInputs = [
      config.systemd.package
      pkgs.coreutils
    ];
    text = ''
      case "''${1-}" in
        start)
          exec systemctl start --no-block ${unitName}.service
          ;;
        status)
          systemctl show --property=ActiveState,Result,ExecMainStartTimestamp,ExecMainExitTimestamp \
            ${unitName}.service
          tail -n 40 ${logFile} 2>/dev/null || true
          ;;
        *)
          echo "usage: ${unitName} start|status" >&2
          exit 2
          ;;
      esac
    '';
  };

  # ExecStopPost. The token goes to curl on stdin, not in its arguments.
  notify = pkgs.writeShellScript "${unitName}-notify" ''
    set -euo pipefail
    token=$(< ${config.sops.secrets."openclaw/telegram-bot-token".path})
    chat=$(< ${config.sops.secrets."openclaw/telegram-owner-id".path})
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" \
      | ${lib.getExe pkgs.curl} --config - -fsS -o /dev/null \
          --data-urlencode "chat_id=$chat" \
          --data-urlencode "text=${config.networking.hostName} rebuild from ${cfg.rebuild.flake}: $SERVICE_RESULT"
  '';
in
{
  options.my.openclaw.rebuild.flake = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "github:alice/dotfiles#hoard";
    description = ''
      Flake output the agent may switch this host to; null keeps rebuilds
      from the agent off. Point it at a branch the agent cannot push to.
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.rebuild.flake != null) {
    # modelled on nixos-upgrade.service (system.autoUpgrade)
    systemd.services.${unitName} = {
      description = "Rebuild from ${cfg.rebuild.flake} for OpenClaw";
      # the switch must not restart or stop the run performing it
      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = config.nix.envVars // {
        HOME = "/root";
      };
      path = with pkgs; [
        coreutils
        gnutar
        xz.bin
        gzip
        gitMinimal
        config.nix.package.out
        # distributed builds reach their builders over SSH
        config.programs.ssh.package
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --refresh --flake ${cfg.rebuild.flake}";
        # world-readable, for `openclaw-rebuild status`
        StandardOutput = "truncate:${logFile}";
        StandardError = "inherit";
        ExecStopPost = lib.optional cfg.telegram.enable "${notify}";
      };
    };

    # the gateway user may start this one unit, and nothing else
    security.polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function (action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              action.lookup("unit") == "${unitName}.service" &&
              action.lookup("verb") == "start" &&
              subject.user == "${gw.user}") {
            return polkit.Result.YES;
          }
        });
      '';
    };

    my.openclaw = {
      hostTools = [ command ];
      # starting a rebuild still asks the owner
      hostExec.allowlist = [
        {
          pattern = unitName;
          argPattern = "^status$";
        }
      ];
      skills.${unitName} = {
        description = "Rebuild and switch this host (${config.networking.hostName}) to its NixOS config on GitHub.";
        text = ''
          `${unitName} start` switches ${config.networking.hostName} to
          `${cfg.rebuild.flake}`, the config as merged on GitHub, not any local
          checkout. Changes must be merged there first. It asks the owner for
          approval, returns at once and runs in the background; the switch may
          restart this gateway mid-turn, and the owner gets a Telegram message
          when it ends.

          `${unitName} status` shows whether the last run is still going, how it
          ended, and the end of its log. Check it before starting another run.
        '';
      };
    };
  };
}
