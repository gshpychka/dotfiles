{ lib, ... }:
{
  # home-manager configuration defaults
  home.preferXdgDirectories = lib.mkDefault true;
  programs.home-manager.enable = lib.mkDefault true;
}

