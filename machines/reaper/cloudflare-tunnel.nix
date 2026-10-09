{ config, lib, ... }:
let
  inherit (config.my) spire;
in
{
  # Only the SPIRE issuer's discovery documents are public; reaper accepts no
  # inbound connections for them, cloudflared dials out to Cloudflare.
  config = lib.mkIf spire.enable {
    services.cloudflared = {
      enable = true;
      # infra/reaper/tunnel.tf creates the tunnel, then:
      # sops exec-file --no-fifo secrets/common/cloudflare-cert.pem 'env TUNNEL_ORIGIN_CERT={} cloudflared tunnel token --cred-file creds.json reaper-tunnel'
      # and encrypt creds.json into secrets/reaper/cloudflare-tunnel.json
      tunnels.reaper-tunnel = {
        credentialsFile = config.sops.secrets.cloudflare-tunnel.path;
        default = "http_status:404";
        ingress = {
          # each hostname needs a proxied CNAME to the tunnel in infra/reaper/dns.tf
          ${spire.issuerHost} = {
            service = "http://${spire.discovery.address}";
            path = "^(${lib.concatMapStringsSep "|" lib.escapeRegex spire.discovery.paths})$";
            # the provider answers only for hosts in its `domains`
            originRequest.httpHostHeader = spire.issuerHost;
          };
        };
      };
    };

    sops.secrets.cloudflare-tunnel = {
      sopsFile = ../../secrets/reaper/cloudflare-tunnel.json;
      restartUnits = [ "cloudflared-tunnel-reaper-tunnel.service" ];
      mode = "0440";
      format = "json";
      key = ""; # we want the entire file
    };
  };
}
