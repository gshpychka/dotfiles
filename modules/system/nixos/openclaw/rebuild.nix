# Lets the OpenClaw agent rebuild this host the usual way, from its own
# checkout and without asking: `openclaw-rebuild switch --flake .#hoard` takes
# nixos-rebuild's arguments. This gives the agent root on this host.
#
# nixos-rebuild runs as a transient unit, not under the gateway: the gateway
# unit's sandbox keeps /nix and /etc read-only, and a switch that restarts the
# gateway would otherwise kill the rebuild performing it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  name = "openclaw-rebuild";
  logFile = "/var/log/${name}.log";

  # what nixos-rebuild needs, as in nixos-upgrade.service (system.autoUpgrade)
  rebuildPath = with pkgs; [
    coreutils
    gnutar
    xz.bin
    gzip
    gitMinimal
    config.nix.package.out
    # distributed builds reach their builders over SSH
    config.programs.ssh.package
  ];

  # ends the log with how the run went, for when the switch restarted the
  # gateway before openclaw-rebuild returned
  logResult = pkgs.writeShellScript "${name}-log-result" ''
    echo "${name}: $SERVICE_RESULT" >> ${logFile}
  '';

  # Runs as root through sudo. The fixed unit name refuses a second rebuild
  # while one runs.
  asRoot = pkgs.writeShellScript "${name}-as-root" ''
    status=0
    ${config.systemd.package}/bin/systemd-run --unit=${name} --quiet --collect --wait --same-dir \
      --property=StandardOutput=truncate:${logFile} \
      --property=StandardError=inherit \
      --property=ExecStopPost=${logResult} \
      --setenv=HOME=/root \
      --setenv=PATH=${lib.makeBinPath rebuildPath} \
      -- ${config.system.build.nixos-rebuild}/bin/nixos-rebuild "$@" || status=$?
    ${pkgs.coreutils}/bin/tail -n 40 ${logFile}
    exit "$status"
  '';

  command = pkgs.writeShellScriptBin name ''
    exec ${config.security.wrapperDir}/sudo -n ${asRoot} "$@"
  '';
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
            command = "${asRoot}";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    my.openclaw = {
      hostTools = [ command ];
      hostExec.allowlist = [
        { pattern = name; }
        {
          pattern = "tail";
          argPattern = "^-n [0-9]+ ${lib.escapeRegex logFile}$";
        }
      ];
      skills.${name} = {
        description = "Rebuild and switch this host (${config.networking.hostName}) from a checkout of its NixOS config.";
        text = ''
          `${name}` is `nixos-rebuild` run as root, with the same arguments,
          from the current directory: in a checkout of the owner's dotfiles,
          `${name} switch --flake .#${config.networking.hostName}`. It waits
          for the run and prints the end of its log. New files must be
          `git add`ed before nix sees them.

          A switch may restart this gateway mid-turn. The run carries on
          regardless; `tail -n 40 ${logFile}` then shows how it ended, on its
          last line.
        '';
      };
    };
  };
}
