{
  config,
  ...
}:
{
  services.cloudflared = {
    enable = true;
    # The tunnel itself is managed in Terraform (infra/buoy/tunnel.tf,
    # config_src = "local"); ingress/routing stays here. Credentials come from
    # the sops file below, matching the Terraform-managed tunnel id + secret.
    tunnels.buoy-tunnel = {
      credentialsFile = config.sops.secrets.cloudflare-tunnel.path;
      default = "http_status:404";
      ingress = {
        # DNS for tunnel hostnames is declared in infra/buoy/dns.tf (proxied
        # CNAMEs to <tunnel-id>.cfargotunnel.com), not `cloudflared tunnel route dns`.
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
