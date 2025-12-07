{
  config,
  ...
}:
let
  uptimeKumaPort = config.services.uptime-kuma.settings.PORT;
in
{
  services.cloudflared = {
    enable = true;
    certificateFile = config.sops.secrets.cloudflare-cert.path;
    # cloudflared tunnel create buoy-tunnel
    tunnels.buoy-tunnel = {
      credentialsFile = config.sops.secrets.cloudflare-tunnel.path;
      default = "http_status:404";
      ingress = {
        "status.${config.my.domain}" = "http://localhost:${uptimeKumaPort}";
      };
    };
  };

  sops.secrets = {
    cloudflare-cert = {
      sopsFile = ../../secrets/common/cloudflare-cert.pem;
      mode = "0440";
      format = "binary";
    };
    cloudflare-tunnel = {
      sopsFile = ../../secrets/buoy/cloudflare-tunnel.json;
      mode = "0440";
      format = "json";
      key = ""; # we want the entire file
    };
  };
}
