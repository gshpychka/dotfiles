{ pkgs, ... }:
{
  # nixos-hardware doesn't have a binary cache, so the kernel is build from source
  # we use the generic kernel from nixpkgs instead
  # https://github.com/NixOS/nixos-hardware/issues/325
  boot.kernelPackages = pkgs.linuxPackages;
}
