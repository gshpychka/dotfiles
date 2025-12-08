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
  };

  # Bind mount the service's state directory to persistent storage
  fileSystems."/var/lib/${config.systemd.services.gatus.serviceConfig.StateDirectory}" = {
    device = "${config.fileSystems.data.mountPoint}/${config.systemd.services.gatus.serviceConfig.StateDirectory}";
    fsType = "none";
    options = [ "bind" ];
  };

  services.gatus = {
    enable = true;
    environmentFile = config.sops.secrets.gatus-env.path;
    settings = {
      web.address = "127.0.0.1";
      security.basic = {
        username = "\${GATUS_USERNAME}";
        password-bcrypt-base64 = "\${GATUS_PASSWORD_BCRYPT_BASE64}";
      };
      storage = {
        type = "sqlite";
        path = "data.db";
      };
      endpoints = [
        {
          name = "Ping";
          url = "icmp://1.1.1.1";
          interval = "1m";
          conditions = [ "[CONNECTED] == true" ];
        }
      ];
    };
  };

  sops.secrets.gatus-env = {
    sopsFile = ../../secrets/buoy/gatus.env;
    format = "dotenv";
  };

  systemd.tmpfiles.rules = [
    "d ${config.fileSystems.data.mountPoint}/${config.systemd.services.gatus.serviceConfig.StateDirectory} 0750 root root"
  ];
}
