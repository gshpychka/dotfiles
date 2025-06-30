{ config, ... }:
# System-level Nix and nixpkgs configuration.
{
  config = {
    nix = {
      channel.enable = false;
      settings = {
        allowed-users = [ config.my.user ];
        trusted-users = [ config.my.user ];
        extra-substituters = [ "https://nix-community.cachix.org" ];
        extra-trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
        experimental-features = [
          "nix-command"
          "flakes"
        ];
      };
    };
    nixpkgs.config = {
      allowUnfree = true;
    };
    nixpkgs.overlays = [
      (import ../../../overlays)
    ];
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };
  };
}