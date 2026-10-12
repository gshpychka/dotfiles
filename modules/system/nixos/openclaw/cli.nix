# `openclaw`, the operator CLI, run as the gateway user with the unit's
# environment.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  gw = config.services.openclaw-gateway;
  environment = gw.environment // {
    OPENCLAW_CONFIG_PATH = gw.configPath;
    OPENCLAW_STATE_DIR = gw.stateDir;
  };

  cli = pkgs.writeShellApplication {
    name = "openclaw";
    text = ''
      if [ "$(id -un)" != ${gw.user} ]; then
        exec sudo -H -u ${gw.user} -- "$0" "$@"
      fi
      # Node fails to spawn children (ffmpeg) from a working directory the
      # gateway user cannot enter
      [ -x . ] || cd ${gw.stateDir}
      ${lib.toShellVars environment}
      export ${lib.concatStringsSep " " (lib.attrNames environment)}
      set -a
      ${lib.concatMapStrings (file: ''
        # shellcheck disable=SC1091
        . ${file}
      '') gw.environmentFiles}
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
