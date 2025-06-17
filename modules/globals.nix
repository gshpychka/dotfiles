{ lib, ... }:

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
  };
  config = {
    time.timeZone = "Europe/Kyiv";
    nix = {
      channel.enable = false;
      settings = {
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
  };
}
