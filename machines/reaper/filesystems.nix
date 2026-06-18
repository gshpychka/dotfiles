{
  fileSystems."/" = {
    label = "nixos";
    fsType = "ext4";
  };

  # Shared boot partition
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/D6D6-CDCD";
    fsType = "vfat";
    # keep the ESP readable by root only
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];

}
