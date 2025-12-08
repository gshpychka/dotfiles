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
          name = "Internet";
          url = "icmp://wan.glib.sh";
          interval = "30s";
          ui.hide-hostname = true;
          conditions = [ "[CONNECTED] == true" ];
        }
        {
          name = "Overseerr";
          url = "https://overseerr.glib.sh";
          interval = "30s";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 5000"
          ];
        }
        {
          name = "Plex";
          url = "http://\${PLEX_HOST}:\${PLEX_PORT}/web/index.html";
          interval = "30s";
          ui.hide-url = true;
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 5000"
          ];
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
