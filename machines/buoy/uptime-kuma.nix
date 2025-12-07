{
  config,
  lib,
  ...
}:
{
  # Mount persistent data disk
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-id/google-data";
    fsType = "ext4";
    autoFormat = true;
  };

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = "127.0.0.1";
      PORT = "3001";
      DATA_DIR = lib.mkForce "${config.fileSystems."/mnt/data".mountPoint}/uptime-kuma";
    };
  };

  users.users.uptime-kuma = {
    isSystemUser = true;
    group = "uptime-kuma";
  };
  users.groups.uptime-kuma = {
    name = config.users.users.uptime-kuma.group;
  };

  systemd.services.uptime-kuma.serviceConfig = {
    # DynamicUser breaks with a persistent disk since files are owned by the old UID
    DynamicUser = lib.mkForce false;
    User = config.users.users.uptime-kuma.name;
    Group = config.users.users.uptime-kuma.group;
  };

  # data dir is owned by root:root, so we need to fix that
  systemd.tmpfiles.rules = [
    "d ${config.services.uptime-kuma.settings.DATA_DIR} 0740 ${config.users.users.uptime-kuma.name} ${config.users.groups.uptime-kuma.name}"
  ];
}
