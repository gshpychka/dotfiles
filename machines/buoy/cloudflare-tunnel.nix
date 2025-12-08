{
  config,
  ...
}:
{
  services.cloudflared = {
    enable = true;
    certificateFile = config.sops.secrets.cloudflare-cert.path;
    # cloudflared tunnel create buoy-tunnel
    tunnels.buoy-tunnel = {
      credentialsFile = config.sops.secrets.cloudflare-tunnel.path;
      default = "http_status:404";
      ingress = {
        # cloudflared tunnel route dns buoy-tunnel <hostname>
        "status.${config.my.domain}" = "http://localhost:${toString config.services.gatus.settings.web.port}";
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
