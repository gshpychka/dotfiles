{
  config,
  lib,
  options,
  inputs,
  ...
}:
{
  config = lib.mkMerge [
    {
      nix = {
        channel.enable = false;
        settings = {
          allowed-users = [ config.my.user ];
          trusted-users = [ config.my.user ];

          extra-substituters = [
            "https://nix-community.cachix.org"
            "https://cache.numtide.com"
          ];
          extra-trusted-public-keys = [
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
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
      nixpkgs.overlays = import ../../../overlays inputs;
    }

    # Only configure home-manager if the module is loaded
    (lib.optionalAttrs (options ? home-manager) {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
      };
    })
  ];
}
