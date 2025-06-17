{ config, pkgs, ... }:
{
  imports = [
    ./system.nix
    ./window-management.nix
    ./homebrew.nix
    ./nix.nix
    ./1password.nix
    ../../modules/touch-id.nix
  ];

  networking = {
    hostName = "eve";
    computerName = "Eve";
  };

  users.users.${config.my.user} = {
    home = "/Users/${config.my.user}";
    shell = pkgs.zsh;
  };
  system.stateVersion = 4;
}
