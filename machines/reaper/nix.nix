{ config, ... }:
{
  nix.settings = {
    allowed-users = [ config.my.user ];
    trusted-users = [ config.my.user ];

    auto-optimise-store = true;
    accept-flake-config = true;
    http-connections = 0;
    download-buffer-size = 500000000;
    extra-substituters = [ "https://cuda-maintainers.cachix.org" ];
    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };
  nix.gc = {
    dates = "weekly";
    automatic = true;
    options = "--delete-older-than 7d";
  };
}
