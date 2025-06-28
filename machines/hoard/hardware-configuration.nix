{
  lib,
  modulesPath,
  config,
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
        # parted /dev/sdc --script mklabel gpt mkart primary 0% 100%
        # cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --sector-size 4096 /dev/sdc1
        # cryptsetup config --label="hoard-alpha-enc" /dev/sdc1
        # systemd-cryptenroll --tpm2-device=auto /dev/sdc1
        # cryptsetup luksOpen /dev/sdc1 hoard-alpha

        # On first device:
        # mkfs.btrfs -d raid0 -m raid1 -L hoard -s 4096 -n 65536 --csum xxhash /dev/mapper/hoard-beta

        # On second device:
        # btrfs device add /dev/mapper/hoard-alpha /mnt/hoard
        # btrfs balance start --full-balance --bg /mnt/hoard
        hoard-alpha = {
          device = "/dev/disk/by-label/hoard-alpha-enc";
          crypttabExtraOpts = [
            "tpm2-device=auto"
            # make it wait for the USB enclosure to show up
            "x-systemd.device-timeout=10s"
            # continue with boot if it doesn't show up
            # nofail
            # nofail breaks the setup - it will not wait for the USB device to show up
            # https://github.com/systemd/systemd/issues/27321#issuecomment-1543226472
          ];
        };
        hoard-beta = {
          device = "/dev/disk/by-label/hoard-beta-enc";
          crypttabExtraOpts = [
            "tpm2-device=auto"
            "x-systemd.device-timeout=10s"
          ];
        };
        trove = {
          device = "/dev/disk/by-label/trove-enc";
          crypttabExtraOpts = [
            "tpm2-device=auto"
            "x-systemd.device-timeout=10s"
            "nofail"
          ];
        };
        oasis = {
          device = "/dev/disk/by-label/oasis-enc";
          crypttabExtraOpts = [
            "tpm2-device=auto"
            "x-systemd.device-timeout=10s"
          ];
          allowDiscards = true;
          bypassWorkqueues = true;
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
        "compress=zstd:1"
        "noatime"
        "lazytime"
        # give it ample time to unlock before continuing
        "x-systemd.device-timeout=10s"
        "nofail"
      ];
    };

    "/mnt/oasis" = {
      device = "/dev/mapper/oasis";
      fsType = "ext4";
      options = [
        "noatime"
        "x-systemd.device-timeout=10s"
        "nofail"
      ];
    };

    "/mnt/trove" = {
      device = "/dev/mapper/trove";
      fsType = "ext4";
      options = [
        "noatime"
        "x-systemd.device-timeout=10s"
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

  my.disk-spindown = {
    enable = true;
    devices = [
      config.boot.initrd.luks.devices.hoard-alpha.device
      config.boot.initrd.luks.devices.hoard-beta.device
    ];
    timeoutMinutes = 5;
  };

  # Monthly btrfs scrubbing to detect corruption
  # We can't repaid it since we're in RAID0,
  # but I guess it would be nice to know
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [
      # this is just "/mnt/hoard", but doing it this way to be a bit safer
      config.fileSystems."/mnt/hoard".mountPoint
    ];
    interval = "monthly";
  };

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
