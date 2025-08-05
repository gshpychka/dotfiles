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
      # run once:
      # sudo sbctl create-keys
      # sudo sbctl enroll-keys --microsoft
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
