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

  # the unit's environment as a shell file: its variables, then the files it loads
  environment = pkgs.writeText "openclaw-environment.sh" (
    lib.concatLines (
      [
        (lib.toShellVars (
          gw.environment
          // {
            OPENCLAW_CONFIG_PATH = gw.configPath;
            OPENCLAW_STATE_DIR = gw.stateDir;
          }
        ))
      ]
      ++ map (file: ". ${file}") gw.environmentFiles
    )
  );

  cli = pkgs.writeShellApplication {
    name = "openclaw";
    text = ''
      if [ "$(id -un)" != ${gw.user} ]; then
        exec sudo -H -u ${gw.user} -- "$0" "$@"
      fi
      # Node fails to spawn children (ffmpeg) from a working directory the
      # gateway user cannot enter
      [ -x . ] || cd ${gw.stateDir}
      set -a
      # shellcheck disable=SC1091
      . ${environment}
      set +a
      exec ${lib.getExe' gw.package "openclaw"} "$@"
    '';
  };
in
{
  config = lib.mkIf config.my.openclaw.enable {
    environment.systemPackages = [ cli ];
  };
}
