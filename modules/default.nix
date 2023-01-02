{ config, pkgs, lib, inputs, ... }: {
  nixpkgs.overlays = [
    (import ./forgit.nix inputs)
  ];
}
