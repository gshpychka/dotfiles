{
  lib,
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
  };
  services.fstrim.enable = true;

}
