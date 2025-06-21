{ ... }:
{
  nix = {
    settings = {
      # originally motivated by https://github.com/NixOS/nixpkgs/pull/369588?new_mergebox=true#issuecomment-2566272567
      sandbox = "relaxed";
      # https://github.com/NixOS/nix/issues/7273
      auto-optimise-store = false;
      accept-flake-config = true;
      http-connections = 0;
      download-buffer-size = 500000000;
    };
    gc = {
      automatic = true;
      interval = {
        Hour = 12;
      };
      options = "--delete-old";
    };
  };
}
