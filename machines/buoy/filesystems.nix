{
  config,
  ...
}:
{
  fileSystems.data = {
    mountPoint = "/mnt/data";
    # /dev/sdb because /dev/disk/by-id/ isn't available in initrd
    device = "/dev/sdb";
    fsType = "ext4";
    autoFormat = true;
    neededForBoot = true;
  };

  # state directories go onto persistent disk
  fileSystems."/var/lib" = {
    # directory created by the bootstrap image
    device = "${config.fileSystems.data.mountPoint}/var-lib";
    fsType = "none";
    options = [ "bind" ];
    depends = [ config.fileSystems.data.mountPoint ];
  };
}
