# Bootstrap:
# flash .#iso to USB, boot hoard
# ssh nixos@iso
# lsblk   # find internal SSD <disk> (~477G), partitions <disk>1 <disk>2 <disk>3
# sgdisk -Z <disk> && sgdisk -n1:0:+1G -t1:EF00 -n2:0:+8G -t2:8200 -n3:0:0 <disk>
# mkfs.fat -F32 -n boot <disk>1 && mkswap -L swap <disk>2 && mkfs.ext4 -L nixos <disk>3
# mount /dev/disk/by-label/nixos /mnt && mount -m /dev/disk/by-label/boot /mnt/boot
# mkdir -p /mnt/etc/ssh && ssh-keygen -t ed25519 -N "" -f /mnt/etc/ssh/ssh_host_ed25519_key
# mkdir -p /mnt/etc/secrets/initrd   # initrd LUKS-unlock keys (boot.nix)
# ssh-keygen -t ed25519 -N "" -f /mnt/etc/secrets/initrd/ssh_host_ed25519_key
# ssh-keygen -t rsa -N "" -f /mnt/etc/secrets/initrd/ssh_host_rsa_key
# nix-shell -p ssh-to-age --run 'ssh-to-age -i /mnt/etc/ssh/ssh_host_ed25519_key.pub'   # → hoard_host
# on eve: set .sops.yaml hoard_host
#         nix shell nixpkgs#sops nixpkgs#gnupg -c find secrets -type f -exec sops updatekeys -y {} \;   # YubiKey plugged in
#         git commit -am rekey && git push
# nixos-install --flake github:gshpychka/dotfiles#hoard && reboot
# encrypted media drives + TPM2 enrollment: see filesystems.nix
{
  pkgs,
  config,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./boot.nix
    ./nix.nix
    ./networking.nix
    ./filesystems.nix
    ./users.nix
    ./frontend.nix
    ./monitoring.nix
    ./downloaders.nix
    ./media.nix
    ./smb.nix
    ./arr-stack
    ./io-scheduling.nix
    ./docker.nix
    ./home.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "24.11";

  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    cryptsetup
  ];

  sops = {
    defaultSopsFile = ../../secrets/hoard/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  my.acme.enable = true;

  my.terminfo.enable = true;

  programs = {
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    zsh = {
      enable = true;
      enableCompletion = false;
      enableBashCompletion = false;
      enableLsColors = false;
    };
  };

  networking.firewall.allowedTCPPorts = [
    config.services.nginx.defaultHTTPListenPort
    config.services.nginx.defaultSSLListenPort
  ];
}
