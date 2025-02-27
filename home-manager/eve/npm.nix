{
  config,
  lib,
  ...
}: {
  home.file.".npm-packages/.keep".source = builtins.toFile "keep" "";
  home.sessionVariables = {
    NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm";
  };

  xdg.configFile = {
    "npm/.npmrc" = {
      text = let
        npmrcGenerator = npmrc: let
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
}
