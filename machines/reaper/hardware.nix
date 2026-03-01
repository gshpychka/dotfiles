{
  lib,
  config,
  pkgs,
  ...
}:
let
  gamingEnabled = config.my.gaming.enable;
in
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
    xone.enable = gamingEnabled;
    steam-hardware.enable = gamingEnabled;
    openrazer = {
      enable = gamingEnabled;
    };
    keyboard = {
      qmk = {
        enable = true;
        keychronSupport = true;
      };
    };
  };
  services.fstrim.enable = true;
  environment.systemPackages = lib.optionals gamingEnabled [ pkgs.headsetcontrol ];
  services.udev.packages = lib.optionals gamingEnabled [ pkgs.headsetcontrol ];
}
