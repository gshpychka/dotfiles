# `openclaw` on the host's PATH: the gateway's own CLI, run as the gateway user
# in the unit's environment, so that it acts on this host's gateway, its config
# and its state.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  gw = config.services.openclaw-gateway;

  # the unit's variables; configPath and stateDir are its OPENCLAW_CONFIG_PATH
  # and OPENCLAW_STATE_DIR
  variables = gw.environment // {
    OPENCLAW_CONFIG_PATH = gw.configPath;
    OPENCLAW_STATE_DIR = gw.stateDir;
  };

  # a shell file exporting the unit's environment: its variables, then the
  # files it loads, under `set -a` so that their variables are exported too
  environment = pkgs.writeText "openclaw-environment.sh" (
    lib.concatLines (
      lib.mapAttrsToList (name: value: "export ${lib.toShellVar name value}") variables
      ++ [ "set -a" ]
      ++ map (file: ". ${file}") gw.environmentFiles
      ++ [ "set +a" ]
    )
  );

  cli = pkgs.writeShellApplication {
    name = "openclaw";
    text = ''
      # `id -un` is the current user; any but the gateway user re-runs this script as it
      if [ "$(id -un)" != ${gw.user} ]; then
        # this script again ("$0" "$@") as the gateway user with its home (-H); config and state are its alone
        exec sudo -H -u ${gw.user} -- "$0" "$@"
      fi
      # moves out of a directory the gateway user cannot enter (-x), from which Node fails to spawn ffmpeg
      [ -x . ] || cd ${gw.stateDir}
      # the file run in this shell (`.`), which keeps what it exports: the unit's environment
      # shellcheck disable=SC1091
      . ${environment}
      # the gateway package's binary in place of this shell, the arguments passed on
      exec ${lib.getExe' gw.package "openclaw"} "$@"
    '';
  };
in
{
  config = lib.mkIf config.my.openclaw.enable {
    environment.systemPackages = [ cli ];
  };
}
