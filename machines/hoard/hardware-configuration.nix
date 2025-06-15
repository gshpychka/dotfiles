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
        # hoard-alpha = {
        #   device = "/dev/disk/by-label/hoard-alpha-enc";
        #   crypttabExtraOpts = [
        #     "tpm2-device=auto"
        #     "nofail"
        #   ];
        # };
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
      device = "/dev/mapper/hoard-beta";
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
