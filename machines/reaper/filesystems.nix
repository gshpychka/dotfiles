{
  fileSystems."/" = {
    label = "nixos";
    fsType = "ext4";
  };

  # Shared boot partition
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/D6D6-CDCD";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  swapDevices = [ ];

}
