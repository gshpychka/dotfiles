{
  lib,
  pkgs,
  config,
  ...
}:
{
  imports = [ ./nvidia.nix ];

  networking.useDHCP = lib.mkDefault true;
  networking = {
    wireless.enable = false;
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
      users = [ config.my.user ];
    };
  };
  services.fstrim.enable = true;
  environment.systemPackages = [ pkgs.headsetcontrol ];
  services.udev.packages = [ pkgs.headsetcontrol ];
}
