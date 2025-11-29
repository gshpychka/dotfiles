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

          # https://wiki.nixos.org/wiki/Maintainers:Fastly#Cache_v2_plans
          # substituters = lib.mkForce [ "https://aseipp-nix-cache.global.ssl.fastly.net" ];
          extra-substituters = [
            "https://nix-community.cachix.org"
            "https://numtide.cachix.org"
          ];
          extra-trusted-public-keys = [
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ber+6jVvPLB9lOLY9rSEExMl5U="
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
