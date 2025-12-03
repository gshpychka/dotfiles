{ pkgs, ... }:
{
  imports = [
    ../../../modules/home-manager
  ];

  my.ghostty.enable = true;

  home.packages = with pkgs; [ razergenie ];
  programs = {
    firefox.enable = true;
  };
  home.stateVersion = "25.11";
}
