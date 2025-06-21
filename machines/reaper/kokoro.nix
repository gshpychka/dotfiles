{ ... }:
let
  localPort = 8000;
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      kokoro-fastapi = {
        image = "ghcr.io/remsky/kokoro-fastapi-gpu:v0.2.4";
        ports = [ "${toString localPort}:8880" ];
        extraOptions = [
          "--device"
          "nvidia.com/gpu=all"
        ];
      };
    };
  };
  services.nginx.virtualHosts."default".locations = {
    "/kokoro/" = {
      proxyPass = "http://127.0.0.1:${toString localPort}/";
      recommendedProxySettings = true;
    };
  };
}
