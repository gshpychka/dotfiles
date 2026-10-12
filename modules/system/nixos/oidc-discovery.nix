# Publishing half of the fleet's OIDC token issuer: serves the discovery
# document and JWKS that AWS STS fetches to verify tokens. Both are static,
# built from modules/common/oidc-issuer.nix, so this needs no access to the
# signer (modules/system/nixos/oidc-issuer.nix) and can run on the same
# machine or another one.
#
# nginx serves them on a loopback port only root can bind. Exposing them is
# the machine's job: its Cloudflare tunnel routes my.oidcIssuer.host to
# my.oidcIssuer.publisher.origin, passing only the two documents' paths
# (reaper: machines/reaper/cloudflare-tunnel.nix), and DNS points the host at
# that tunnel (reaper: infra/reaper/dns.tf).
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
  port = 81;

  # URL path -> document
  documents = {
    ${cfg.discoveryPath} = cfg.discoveryDocument;
    ${cfg.jwksPath} = cfg.jwks;
  };

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
  options.my.oidcIssuer.publisher = {
    enable = lib.mkEnableOption "publishing the OIDC token issuer's discovery document and JWKS";
    origin = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://127.0.0.1:${toString port}";
      description = "Where the machine's tunnel forwards requests for my.oidcIssuer.host.";
    };
  };

  config = lib.mkIf cfg.publisher.enable {
    services.nginx = {
      enable = true;
      virtualHosts.oidc-discovery = {
        serverName = cfg.host;
        # the only server on this address, so no other vhost is reachable
        # through it whatever Host a request carries
        listen = [
          {
            addr = "127.0.0.1";
            inherit port;
          }
        ];
        root = webRoot;
        # exact matches for the published documents; everything else 404s
        locations = lib.genAttrs (map (path: "= ${path}") (lib.attrNames documents)) (_: { }) // {
          "/".return = "404";
        };
        extraConfig = ''
          default_type application/json;
          add_header Cache-Control "public, max-age=${toString cfg.jwksCacheSeconds}" always;
        '';
      };
    };
  };
}
