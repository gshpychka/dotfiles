{ ... }:
{
  nix.settings = {
    auto-optimise-store = true;
    accept-flake-config = true;
    http-connections = 0;
    download-buffer-size = 500000000;
  };
  nix.gc = {
    dates = "weekly";
    automatic = true;
    options = "--delete-older-than 7d";
  };
}
