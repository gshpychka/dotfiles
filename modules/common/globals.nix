{ lib, config, ... }:
# Global configuration options.
{
  options.my = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "glib.sh";
      description = "Public domain name";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "gshpychka";
      description = "Main username";
    };
    sshKeys = lib.mkOption {
      type = lib.types.submodule {
        options = {
          main = lib.mkOption {
            type = lib.types.str;
            description = "Main SSH public key";
          };
          homeassistant = lib.mkOption {
            type = lib.types.str;
            description = "SSH public key for home assistant";
          };
          gitlab = lib.mkOption {
            type = lib.types.str;
            description = "SSH public key for GitLab";
          };
        };
      };
      description = "SSH public keys";
    };
  };
  config = {
    my.sshKeys = {
      main = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG";
      homeassistant = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAC9nquQBUuHWrWJvuUJLuR2zfupJp+QtQlpck0n5J0J";
      gitlab = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK0TQf0piikNdo54HRg/l6dBXRPM2BmlA4f7EmXJ9uvW";
    };
    time.timeZone = "Europe/Kyiv";
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
      (import ../../overlays)
    ];
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };
  };
}
