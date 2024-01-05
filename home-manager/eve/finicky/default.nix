{config, ...}: let
  filePath = "finicky/config.js";
in {
  xdg.configFile.${filePath} = {
    source = ./config.js;
    onChange = "cat ${config.xdg.configHome}/${filePath} > ${config.home.homeDirectory}/.finicky.js";
  };
}
