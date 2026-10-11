# Rebuilds of this host by the OpenClaw agent, from its own checkout and
# without asking: `sudo nixos-rebuild switch --flake .#<host>`. This gives the
# agent root on this host.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  nixos-rebuild = "/run/current-system/sw/bin/nixos-rebuild";
  # The activation runs in its own unit and outlives a gateway restart, on the
  # caller's stdout and stderr; switch-to-configuration panics writing to a
  # closed pipe.
  logFile = "${cfg.workspace}/nixos-rebuild.log";
in
{
  options.my.openclaw.rebuild.enable = lib.mkEnableOption ''
    rebuilds of this host by the agent, from its own checkout and without
    asking; this gives the agent root'';

  config = lib.mkIf (cfg.enable && cfg.rebuild.enable) {
    security.sudo.extraRules = [
      {
        users = [ gw.user ];
        commands = [
          {
            command = nixos-rebuild;
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    my.openclaw = {
      hostExec.allowlist = [
        {
          pattern = "sudo";
          argPattern = "^nixos-rebuild( |$)";
        }
      ];
      skills.nixos-rebuild = {
        description = "Rebuild and switch this host (${config.networking.hostName}) from a checkout of its NixOS config.";
        text = ''
          In a checkout of the owner's dotfiles, with the output in a file:

              sudo nixos-rebuild switch --flake .#${config.networking.hostName} > ${logFile} 2>&1

          then read `nixos-rebuild.log` in your workspace. New files must be
          `git add`ed before nix sees them.

          Always send the output to a file: a switch may restart this gateway
          mid-turn, and the activation, which carries on regardless, fails if
          its output goes to a closed pipe. After such a restart the log shows
          how the switch ended.
        '';
      };
    };
  };
}
