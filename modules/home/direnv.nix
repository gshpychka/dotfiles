{ config, lib, ... }:
let
  cfg = config.my.direnv;
in
{
  options.my.direnv = {
    enable = lib.mkEnableOption "direnv development environment";
  };

  config = lib.mkIf cfg.enable {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
      enableBashIntegration = false;
      enableFishIntegration = false;
      enableNushellIntegration = false;
    };
  };
}

