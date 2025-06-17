{
  ...
}:
{
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/92e3414f-785b-40fa-bf3a-a72022d7d244";
    fsType = "ext4";
  };

  # Shared boot partition
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/063D-73D8";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  swapDevices = [ ];

}
