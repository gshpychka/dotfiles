{ config, lib, ... }:
let
  inherit (config.my) spire oidcIssuer;
  # The token issuer only needs the tunnel once it has a key to publish, so a
  # fresh setup can deploy and run oidc-issuer-keygen before the tunnel exists.
  publishIssuer = oidcIssuer.publisher.enable && oidcIssuer.publicKeys != [ ];
  pathRegex = paths: "^(${lib.concatMapStringsSep "|" lib.escapeRegex paths})$";
in
{
  # Only the two issuers' discovery documents are public; reaper accepts no
  # inbound connections for them, cloudflared dials out to Cloudflare.
  config = lib.mkIf (spire.enable || publishIssuer) {
    services.cloudflared = {
      enable = true;
      # infra/reaper/tunnel.tf creates the tunnel, then:
      # sops exec-file --no-fifo secrets/common/cloudflare-cert.pem 'env TUNNEL_ORIGIN_CERT={} cloudflared tunnel token --cred-file creds.json reaper-tunnel'
      # and encrypt creds.json into secrets/reaper/cloudflare-tunnel.json
      tunnels.reaper-tunnel = {
        credentialsFile = config.sops.secrets.cloudflare-tunnel.path;
        default = "http_status:404";
        # each hostname needs a proxied CNAME to the tunnel in infra/reaper/dns.tf
        ingress =
          lib.optionalAttrs spire.enable {
            ${spire.issuerHost} = {
              service = "unix:${spire.discovery.socket}";
              path = pathRegex spire.discovery.paths;
              # the provider serves its discovery document only for hosts in
              # its `domains`
              originRequest.httpHostHeader = spire.issuerHost;
            };
          }
          // lib.optionalAttrs publishIssuer {
            ${oidcIssuer.host} = {
              service = oidcIssuer.publisher.origin;
              path = pathRegex [
                oidcIssuer.discoveryPath
                oidcIssuer.jwksPath
              ];
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
