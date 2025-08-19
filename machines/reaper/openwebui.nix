{ config, ... }:
{
  services.open-webui = {
    enable = true;
    host = "127.0.0.1";
    port = 8080;
    environment = {
      OLLAMA_API_BASE_URL = "http://${config.services.ollama.host}:${toString config.services.ollama.port}";
      DEFAULT_USER_ROLE = "user";
    };
  };

  services.nginx.virtualHosts."openwebui" = {
    serverName = "openwebui.${config.networking.fqdn}";
    useACMEHost = config.networking.fqdn;
    onlySSL = true;
    locations."/" = {
      proxyPass = "http://${config.services.open-webui.host}:${toString config.services.open-webui.port}/";
      proxyWebsockets = true;
    };
  };
}
