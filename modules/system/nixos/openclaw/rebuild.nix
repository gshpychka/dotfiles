# Rebuilds of this host by the OpenClaw agent, from its own checkout:
# `openclaw-rebuild switch --flake .#<host>`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  nixos-rebuild = "/run/current-system/sw/bin/nixos-rebuild";
  logFile = "${cfg.workspace}/nixos-rebuild.log";

  rebuild = pkgs.writeShellApplication {
    name = "openclaw-rebuild";
    text = ''
      # The activation runs in its own unit and outlives a gateway restart, on
      # this command's stdout and stderr; switch-to-configuration panics
      # writing to a closed pipe.
      exec >${logFile} 2>&1
      exec ${config.security.wrapperDir}/sudo -n ${nixos-rebuild} "$@"
    '';
  };
in
{
  options.my.openclaw.rebuild.enable = lib.mkEnableOption ''
    rebuilds of this host by the agent, from its own checkout, through its
    root (my.openclaw.root)'';

  config = lib.mkIf (cfg.enable && cfg.rebuild.enable) {
    assertions = [
      {
        assertion = cfg.root.sshKey != null;
        message = "my.openclaw.rebuild runs nixos-rebuild with the agent's sudo, which my.openclaw.root.sshKey grants.";
      }
    ];

    my.openclaw = {
      extraPackages = [ rebuild ];
      skills.nixos-rebuild = {
        description = "Rebuild and switch this host (${config.networking.hostName}) from a checkout of its NixOS config.";
        text = ''
          In a checkout of the owner's dotfiles:

              openclaw-rebuild switch --flake .#${config.networking.hostName}

          It runs `sudo nixos-rebuild` with your arguments and writes all
          output to `nixos-rebuild.log` in your workspace; read the log there.
          New files must be `git add`ed before nix sees them.

          A switch may restart this gateway mid-turn. The switch carries on
          regardless, and after the restart the log shows how it ended.
        '';
      };
    };
  };
}
