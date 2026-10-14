{ config, lib, ... }:
let
  inherit (config.services.oidc-issuer) simple spire;
  # created by infra/reaper
  tunnel = "reaper-tunnel";
in
{
  # Only the two issuers' discovery documents are public; reaper accepts no
  # inbound connections for them, cloudflared dials out to Cloudflare.
  config = lib.mkMerge [
    {
      services.oidc-issuer.simple.cloudflareTunnel = tunnel;
      services.oidc-issuer.spire.cloudflareTunnel = tunnel;
    }

    (lib.mkIf (spire.enable || simple.enable) {
      services.cloudflared = {
        enable = true;
        # infra/reaper creates the tunnel, then:
        # sops exec-file --no-fifo secrets/common/cloudflare-cert.pem 'env TUNNEL_ORIGIN_CERT={} cloudflared tunnel token --cred-file creds.json reaper-tunnel'
        # and encrypt creds.json into secrets/reaper/cloudflare-tunnel.json
        tunnels.${tunnel} = {
          credentialsFile = config.sops.secrets.cloudflare-tunnel.path;
          default = "http_status:404";
        };
      };

      sops.secrets.cloudflare-tunnel = {
        sopsFile = ../../secrets/reaper/cloudflare-tunnel.json;
        restartUnits = [ "cloudflared-tunnel-${tunnel}.service" ];
        mode = "0440";
        format = "json";
        key = ""; # we want the entire file
      };
    })
  ];
}
