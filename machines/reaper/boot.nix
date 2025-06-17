{ pkgs, ... }:
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
    loader = {
      grub.enable = false;
      systemd-boot = {
        enable = true;
        configurationLimit = 2;
      };
      efi.canTouchEfiVariables = true;
      timeout = 3;
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
