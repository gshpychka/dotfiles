# GCE persistent data disk, shared between the runtime config (machines/buoy)
# and the bootstrap image (infra/nixos/configuration.nix): the runtime mount
# must match what the bootstrap image created and populated.
{
  fileSystems.data = {
    mountPoint = "/mnt/data";
    # /dev/sdb because /dev/disk/by-id/ isn't available in initrd
    device = "/dev/sdb";
    fsType = "ext4";
    autoFormat = true;
    neededForBoot = true;
  };
}
