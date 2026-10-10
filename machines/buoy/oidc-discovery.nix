# Public half of reaper's OIDC token issuer (machines/reaper/oidc-issuer): the
# discovery document and JWKS AWS STS fetches to verify reaper's tokens. Both
# are static, built from modules/common/oidc-issuer.nix, so publishing a key is
# a buoy deploy and reaper needs no public endpoint of its own.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.oidcIssuer;
  # Below 1024, so only root can bind it: no other local user can stand in
  # for nginx (and serve its own JWKS to AWS) while nginx is down.
  port = 80;

  # URL path -> document
  documents = {
    ${cfg.discoveryPath} = cfg.discoveryDocument;
    ${cfg.jwksPath} = cfg.jwks;
  };
  paths = lib.attrNames documents;

  webRoot = pkgs.linkFarm "oidc-discovery" (
    lib.mapAttrs' (
      path: document:
      lib.nameValuePair (lib.removePrefix "/" path) (
        pkgs.writeText (baseNameOf path) (builtins.toJSON document)
      )
    ) documents
  );
in
{
  services.nginx = {
    enable = true;
    virtualHosts.oidc-discovery = {
      serverName = cfg.host;
      listen = [
        {
          addr = "127.0.0.1";
          inherit port;
        }
      ];
      root = webRoot;
      # exact matches for the published documents; everything else 404s
      locations = lib.genAttrs (map (path: "= ${path}") paths) (_: { }) // {
        "/".return = "404";
      };
      extraConfig = ''
        default_type application/json;
        add_header Cache-Control "public, max-age=${toString cfg.jwksCacheSeconds}" always;
      '';
    };
  };

  # infra/buoy/dns.tf points cfg.host at this tunnel; only the documents'
  # paths reach nginx
  services.cloudflared.tunnels.buoy-tunnel.ingress.${cfg.host} = {
    service = "http://127.0.0.1:${toString port}";
    path = "^(${lib.concatMapStringsSep "|" lib.escapeRegex paths})$";
  };
}
