{ lib, ... }:
# Shared nix-daemon defaults for NixOS machines. eve (darwin) diverges enough
# to keep its own settings - see machines/eve/nix.nix.
# download-buffer-size stays per-machine: it is sized to each machine's RAM.
{
  nix = {
    gc = {
      automatic = lib.mkDefault true;
      dates = lib.mkDefault "weekly";
      options = lib.mkDefault "--delete-older-than 7d";
    };
    settings = {
      auto-optimise-store = lib.mkDefault true;
      accept-flake-config = lib.mkDefault true;
      http-connections = lib.mkDefault 0;
    };
  };
}
