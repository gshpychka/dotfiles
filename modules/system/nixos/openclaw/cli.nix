# `openclaw` on the host's PATH: the gateway's CLI, acting as the gateway user
# on this host's gateway, its config and its state.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;

  # the gateway unit's environment as a shell file
  unitEnvironment = pkgs.writeText "openclaw-environment.sh" (
    lib.concatLines (
      lib.mapAttrsToList (
        name: value: "export ${lib.toShellVar name value}"
      ) config.systemd.services.${gw.unitName}.environment
      # exports each NAME=value line of the file as data
      ++ map (
        file: ''while IFS= read -r variable; do export "$variable"; done < ${file}''
      ) gw.environmentFiles
    )
  );

  cli = pkgs.writeShellApplication {
    name = "openclaw";
    # the environment file it runs lies outside shellcheck's input
    excludeShellChecks = [ "SC1091" ];
    text = ''
      # whether the current user (`id -un`) is someone other than the gateway user
      if [ "$(${lib.getExe' pkgs.coreutils "id"} -un)" != ${gw.user} ]; then
        # replaces this shell (`exec`) with this script ("$0") and its arguments ("$@"), run as the gateway user (`sudo -u`)
        exec ${config.security.wrapperDir}/sudo -u ${gw.user} "$0" "$@"
      fi
      # whether the current user cannot enter (`! -x`) the working directory (`.`)
      if ! [ -x . ]; then
        # moves (`cd`) to the unit's working directory: OpenClaw hands its child processes the working directory explicitly, which they must be able to enter
        cd ${gw.workingDirectory}
      fi
      # runs the unit's environment file in this shell (`.`), which keeps the variables it exports
      . ${unitEnvironment}
      # replaces this shell (`exec`) with the gateway's `openclaw`, given this script's arguments ("$@")
      exec ${lib.getExe gw.package} "$@"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cli ];
  };
}
