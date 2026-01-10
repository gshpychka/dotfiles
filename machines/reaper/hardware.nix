{
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./nvidia.nix ];

  networking.useDHCP = lib.mkDefault true;
  networking = {
    # force disable wireless to prevent conflicts with networkmanager
    wireless.enable = lib.mkForce false;
  };
  hardware = {
    bluetooth.enable = true;
    gpgSmartcards.enable = true;
    enableAllFirmware = true;
    cpu.intel.updateMicrocode = true;
    graphics = {
      enable = true;
    };
    xone.enable = true;
    steam-hardware.enable = true;
    openrazer = {
      enable = true;
    };
    keyboard = {
      qmk = {
        enable = true;
        keychronSupport = true;
      };
    };
  };
  services.fstrim.enable = true;
  environment.systemPackages = [ pkgs.headsetcontrol ];
  services.udev.packages = [ pkgs.headsetcontrol ];
}
