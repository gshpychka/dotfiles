{
  config,
  ...
}:
let
  inherit ((import ./ports.nix { inherit config; })) ports;
in
{
  services = {
    cloudflared = {
      enable = true;
      certificateFile = config.sops.secrets.cloudflare-cert.path;
      # cloudflared tunnel create hoard-tunnel
      tunnels.hoard-tunnel = {
        default = "http_status:404";
        credentialsFile = config.sops.secrets.cloudflare-tunnel.path;
        ingress = {
          # cloudflared tunnel route dns hoard-tunnel <hostname>
          "overseerr.${config.networking.domain}" = "http://localhost:${ports.overseerr}";
          "tautulli.${config.networking.domain}" = "http://localhost:${ports.tautulli}";
        };
      };
    };
    nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts =
        let
          services = [
            "qbittorrent"
            "radarr"
            "sonarr"
            "lidarr"
            "prowlarr"
            "sabnzbd"
            "home"
            "glances"
            "tautulli"
            "overseerr"
            "jellyfin"
          ];

          serviceToVhost = name: {
            name = name;
            value = {
              serverName = "${name}.${config.networking.fqdn}";
              useACMEHost = config.networking.fqdn;
              onlySSL = true;
              locations."/" = {
                proxyPass = "http://127.0.0.1:${ports.${name}}/";
              };
            };
          };

          vhosts = builtins.listToAttrs (map serviceToVhost services);
        in
        vhosts;
    };
  };

  sops.secrets = {
    cloudflare-tunnel = {
      sopsFile = ../../secrets/hoard/cloudflare-tunnel.json;
      mode = "0440";
      format = "json";
      key = ""; # we want the entire file
    };
    cloudflare-cert = {
      sopsFile = ../../secrets/hoard/cloudflare-cert.pem;
      mode = "0440";
      format = "binary";
    };
  };
}