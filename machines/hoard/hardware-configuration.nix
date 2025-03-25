{
  lib,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  boot = {
    initrd = {
      availableKernelModules = ["xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod"];
    };
    kernelModules = ["kvm-intel"];
    extraModulePackages = [];
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    options = ["noatime"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  fileSystems."/mnt/hoard" = {
    device = "/dev/disk/by-label/hoard";
    fsType = "ext4";
    options = [
      "noatime" # don't update atime on read
      "data=writeback" # skip data journaling
      "barrier=0" # disable write barriers
      "journal_async_commit" # lower latency journal commits
    ];
  };

  swapDevices = [{device = "/dev/disk/by-label/swap";}];

  hardware.block.defaultScheduler = "kyber";
  hardware.block.defaultSchedulerRotational = "bfq";

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
