{ config, lib, ... }:
{
  services.open-webui = {
    enable = true;
    host = "127.0.0.1";
    port = 8080;
    environment = {
      ENABLE_PERSISTENT_CONFIG = "False";
      ENABLE_SIGNUP = "True";
      DEFAULT_USER_ROLE = "pending"; # users have to be approved by an admin
      ENABLE_VERSION_UPDATE_CHECK = "False";
      WEBUI_URL = "https://openwebui.${config.networking.fqdn}";

      OLLAMA_API_BASE_URL = "http://${config.services.ollama.host}:${toString config.services.ollama.port}";

      # ENABLE_IMAGE_GENERATION = "True";
      # IMAGE_GENERATION_ENGINE = "comfyui";
      # COMFYUI_BASE_URL = "http://${config.services.comfyui.host}:${toString config.services.comfyui.port}/";
    };
  };

  systemd.services.open-webui.requisite =
    lib.optional
      (config.services.open-webui.environment ? OLLAMA_API_BASE_URL)
      config.systemd.services.ollama.name;

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
