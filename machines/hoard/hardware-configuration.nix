{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot = {
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "nvme"
        "usbhid"
        "usb_storage"
        "uas"
        "sd_mod"
      ];
      kernelModules = [
        "r8169" # ethernet driver
      ];
      systemd = {
        enable = true;
        tpm2.enable = true;
      };
      luks.devices = {
        oasis = {
          device = "/dev/disk/by-label/oasis-enc";
          crypttabExtraOpts = [ "tpm2-device=auto" ];
          allowDiscards = true;
          bypassWorkqueues = true;
        };
        # parted /dev/sdc --script mklabel gpt mkart primary 0% 100%
        # cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --sector-size 4096 /dev/sdc1
        # cryptsetup config --label="hoard-alpha-enc" /dev/sdc1
        # systemd-cryptenroll --tpm2-device=auto /dev/sdc1
        # cryptsetup luksOpen /dev/sdc1 hoard-alpha

        # On first device:
        # mkfs.btrfs -d single -m dup -s 4096 -n 65536 --csum xxhash /dev/mapper/hoard-beta

        # On second device:
        # btrfs device add /dev/mapper/hoard-alpha /mnt/hoard
        # btrfs balance start -dconvert=raid0 -mconvert=raid1 /mnt/hoard
        hoard-alpha = {
          device = "/dev/disk/by-label/hoard-alpha-enc";
          crypttabExtraOpts = [
            "tpm2-device=auto"
            "nofail"
          ];
        };
        hoard-beta = {
          device = "/dev/disk/by-label/hoard-beta-enc";
          crypttabExtraOpts = [
            "tpm2-device=auto"
            "nofail"
          ];
        };
        trove = {
          device = "/dev/disk/by-label/trove-enc";
          crypttabExtraOpts = [
            "tpm2-device=auto"
            "nofail"
          ];
        };
      };
    };
    kernelModules = [
      "kvm-intel"
    ];
    extraModulePackages = [ ];
  };

  fileSystems = {
    "/" = {
      label = "nixos";
      fsType = "ext4";
      options = [ "noatime" ];
    };

    "/boot" = {
      label = "boot";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };

    "/mnt/hoard" = {
      # btrfs filesystem label /mnt/hoard hoard
      # this will mount both drives
      label = "hoard";
      fsType = "btrfs";
      options = [
        "noatime"
        "nofail"
        "lazytime"
      ];
    };

    "/mnt/oasis" = {
      device = "/dev/mapper/oasis";
      fsType = "ext4";
      options = [
        "noatime"
      ];
    };

    "/mnt/trove" = {
      device = "/dev/mapper/trove";
      fsType = "ext4";
      options = [
        "noatime"
        "nofail"
      ];
    };
  };

  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

  hardware = {
    gpgSmartcards.enable = true;
    enableAllFirmware = true;
    cpu.intel.updateMicrocode = true;
    usbStorage.manageShutdown = true;
    block = {
      defaultScheduler = "mq-deadline";
      defaultSchedulerRotational = "bfq";
    };
  };

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
