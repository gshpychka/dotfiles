{
  config,
  ...
}:
{
  services.gatus = {
    enable = true;
    environmentFile = config.sops.secrets.gatus-env.path;
    settings = {
      web.address = "127.0.0.1";
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
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
          ui = {
            hide-hostname = true;
            hide-errors = true;
          };
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
}
