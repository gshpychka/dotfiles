{
  config,
  ...
}:
{
  services.cloudflared = {
    enable = true;
    tunnels.buoy-tunnel = {
      # sops exec-file --no-fifo secrets/common/cloudflare-cert.pem 'env TUNNEL_ORIGIN_CERT={} cloudflared tunnel token --cred-file creds.json buoy-tunnel'
      # then encrypt creds.json into secrets/buoy/cloudflare-tunnel.json
      credentialsFile = config.sops.secrets.cloudflare-tunnel.path;
      default = "http_status:404";
      ingress = {
        # each hostname needs a proxied CNAME to the tunnel in infra/buoy/dns.tf
        "status.${config.my.domain}" =
          "http://localhost:${toString config.services.gatus.settings.web.port}";
        "ntfy.${config.my.domain}" = "http://${config.services.ntfy-sh.settings.listen-http}";
        # oidc-discovery.nix adds the OIDC issuer's host
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
