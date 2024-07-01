{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.ghostty;
in {
  options.modules.ghostty = {
    enable = lib.mkEnableOption "ghostty";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkgs.ghostty];
    xdg.configFile = {
      "ghostty/config" = {
        source = ./config;
      };
    };
  };
}
