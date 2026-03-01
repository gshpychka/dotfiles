{
  config,
  lib,
  ...
}:
let
  cfg = config.my.npm;
in
{
  options.my.npm = {
    enable = lib.mkEnableOption "NPM configuration";
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/.npmrc";
      NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
      NPM_CONFIG_TMP = "${config.xdg.cacheHome}/npm/tmp";

    };

    xdg.configFile = {
      "npm/.npmrc" = {
        text =
          let
            npmrcGenerator =
              npmrc:
              let
                formatLine = name: value: "${name}=${toString value}";
                content = lib.concatStringsSep "\n" (lib.mapAttrsToList formatLine npmrc);
              in
              content;

            npmrcConfig = {
              cache = "${config.xdg.cacheHome}/npm";
              prefix = "${config.xdg.dataHome}/.npm-packages";
            };

            generatedNpmrc = npmrcGenerator npmrcConfig;
          in
          generatedNpmrc;
      };
    };
  };
}
