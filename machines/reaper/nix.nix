{ ... }:
{
  nix.settings = {
    auto-optimise-store = true;
    accept-flake-config = true;
    http-connections = 0;
    # https://github.com/NixOS/nix/issues/11728#issuecomment-2725297584
    # 2000MB
    download-buffer-size = 2097152000;
  };
  nix.gc = {
    dates = "weekly";
    automatic = true;
    options = "--delete-older-than 7d";
  };
}
