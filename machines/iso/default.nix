# NixOS bootable installer ISO configuration
#
# Build:
#   nix build .#iso
#
# Find device name with: lsblk or diskutil list (macOS)
#
# Write to USB stick
#   sudo dd if=./result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress && sync
{
  config,
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-base.nix"
  ];

  # SSH into installer via `ssh nixos@iso`
  networking.hostName = "iso";
  services.openssh.enable = true;
  users.users.nixos.openssh.authorizedKeys.keys = [ config.my.sshKeys.main ];

  # potentailly useful utils
  environment.systemPackages = with pkgs; [
    parted
    smartmontools
    efibootmgr
  ];
}
