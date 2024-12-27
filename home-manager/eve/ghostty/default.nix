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
    # TODO: install via homebrew if enabled
    xdg.configFile = {
      "ghostty/config" = {
        source = ./config;
      };
    };
  };
}
