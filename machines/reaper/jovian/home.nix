{ pkgs, ... }:
{
  imports = [
    ../../../modules/home-manager
  ];
  home.stateVersion = "25.11";

  home.packages = with pkgs; [ razergenie ];
  programs = {
    firefox.enable = true;
  };

  my.ghostty.enable = true;
}
