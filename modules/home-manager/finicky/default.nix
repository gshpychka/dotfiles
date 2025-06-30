{ config, lib, ... }:
let
  cfg = config.my.finicky;
  filePath = "finicky/config.js";
in
{
  options.my.finicky = {
    enable = lib.mkEnableOption "Finicky browser chooser";
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile.${filePath} = {
      source = ./config.js;
      # finicky does not support symlinks
      onChange = "cat ${config.xdg.configHome}/${filePath} > ${config.home.homeDirectory}/.finicky.js";
    };
  };
}