{
  config,
  ...
}:
{
  services.cloudflared = {
    enable = true;
    # cloudflared tunnel create buoy-tunnel
    tunnels.buoy-tunnel = {
      credentialsFile = config.sops.secrets.cloudflare-tunnel.path;
      default = "http_status:404";
      ingress = {
        # cloudflared tunnel route dns buoy-tunnel <hostname>
        "status.${config.my.domain}" =
          "http://localhost:${toString config.services.gatus.settings.web.port}";
      };
    };
  };

  sops.secrets = {
    cloudflare-tunnel = {
      sopsFile = ../../secrets/buoy/cloudflare-tunnel.json;
      restartUnits = [ "cloudflared-tunnel-buoy-tunnel.service" ];
      mode = "0440";
      format = "json";
      key = ""; # we want the entire file
    };
  };
}
