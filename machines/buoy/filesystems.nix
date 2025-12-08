{
  config,
  ...
}:
{
  fileSystems.data = {
    mountPoint = "/mnt/data";
    device = "/dev/disk/by-id/google-data";
    fsType = "ext4";
    autoFormat = true;
    neededForBoot = true;
  };

  # state directories go onto persistent disk
  fileSystems."/var/lib" = {
    device = "${config.fileSystems.data.mountPoint}/var-lib";
    fsType = "none";
    options = [ "bind" ];
  };

  # bootstrap the source directory
  systemd.tmpfiles.rules = [
    "d ${config.fileSystems."/var/lib".device} 0755 root root"
  ];
}
