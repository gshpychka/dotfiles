{
  config,
  lib,
  ...
}:
{
  # persistent data disk
  fileSystems.data = {
    mountPoint = "/mnt/data";
    device = "/dev/disk/by-id/google-data";
    fsType = "ext4";
    autoFormat = true;
  };

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = "127.0.0.1";
      PORT = "3001";
      DATA_DIR = lib.mkForce "${config.fileSystems.data.mountPoint}/uptime-kuma";
    };
  };

  users.users.uptime-kuma = {
    isSystemUser = true;
    group = config.users.groups.uptime-kuma.name;
  };
  users.groups.uptime-kuma = { };

  systemd.services.uptime-kuma.serviceConfig = {
    # DynamicUser breaks with a persistent disk since files are owned by the old UID
    DynamicUser = lib.mkForce false;
    User = config.users.users.uptime-kuma.name;
    Group = config.users.users.uptime-kuma.group;
    # (ProtectSystem=strict blocks everything else)
    ReadWritePaths = [ config.services.uptime-kuma.settings.DATA_DIR ];
  };

  # data dir is owned by root:root, so we need to fix that
  systemd.tmpfiles.rules = [
    "d ${config.fileSystems.data.mountPoint} 0755 root root" # it's 0710 by default
    "d ${config.services.uptime-kuma.settings.DATA_DIR} 0740 ${config.systemd.services.uptime-kuma.serviceConfig.User} ${config.systemd.services.uptime-kuma.serviceConfig.Group}"
  ];
}
