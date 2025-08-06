{ pkgs, lib, ... }:
{
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    initrd = {
      availableKernelModules = [
        "vmd"
        "xhci_pci"
        "nvme"
        "thunderbolt"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];

    # Lanzaboote replaces systemd-boot
    loader = {
      grub.enable = false;
      systemd-boot.enable = lib.mkForce false;
      efi.canTouchEfiVariables = true;
      timeout = 3;
    };

    # secure boot
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
      configurationLimit = 10;
      # run once before rebuild:
      # sudo sbctl create-keys
      # run once after rebuild:
      # https://github.com/nix-community/lanzaboote/issues/389#issuecomment-2729324645
      # sudo sbctl enroll-keys --microsoft --ignore-immutable
    };

    # silent and pretty boot
    plymouth = {
      enable = true;
    };
    kernelParams = [
      "quiet"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    initrd.verbose = false;

    tmp = {
      useTmpfs = true;
      tmpfsSize = "32G";
    };
  };
}
