# Declarative cross-service wiring for hoard's *Arr stack (mechanism: my.arrSync, in
# modules/system/nixos/arr-sync.nix). Converges, over each app's REST API:
#   - Prowlarr Applications  -> registers Sonarr/Radarr/Lidarr for indexer push
#   - download clients       -> qBittorrent + SABnzbd in every app
#   - root folders           -> the media library path per *Arr
#
# API keys come from the SOPS secrets pinned in ./auth.nix, so this wiring is plain
# Nix. Resources are matched by name (clients/apps) or path (root folders): existing
# matches are updated in place, missing ones are created, and all others are preserved.
{
  config,
  lib,
  ...
}:
let
  inherit (import ../ports.nix { inherit config; }) ports;

  secret = name: config.sops.secrets.${name}.path;
  secretName = service: "${service}-api-key";
  localUrl = port: "http://localhost:${toString port}";
  gateway = config.my.webGateway;
  hasPlainGatewayVhost =
    service:
    gateway.enable
    && builtins.hasAttr service gateway.services
    && (!gateway.sso.enable || gateway.services.${service}.auth == "native");

  downloadClientUnits = [
    config.systemd.services.qbittorrent.name
    config.systemd.services.sabnzbd.name
  ];

  # Use the vhost only when it exists and accepts a cookie-less client. A
  # gateway-auth vhost behind SSO rejects machine clients, while disabling the
  # whole gateway removes the vhost; both states therefore use loopback. Every
  # field appears in both forms because the engine overlays only listed fields.
  downloadClientEndpoint =
    service:
    if hasPlainGatewayVhost service then
      {
        host = "${service}.${config.networking.fqdn}";
        port = config.services.nginx.defaultSSLListenPort;
        useSsl = true;
      }
    else
      {
        host = "localhost";
        port = ports.${service};
        useSsl = false;
      };

  qbittorrent = category: {
    name = "qBittorrent";
    implementation = "QBittorrent";
    protocol = "torrent";
    fields = downloadClientEndpoint "qbittorrent" // category;
    secretFields = {
      username = secret "qbittorrent-username";
      password = secret "qbittorrent-password";
    };
  };

  sabnzbd = category: {
    name = "SABnzbd";
    implementation = "Sabnzbd";
    protocol = "usenet";
    fields = downloadClientEndpoint "sabnzbd" // category;
    secretFields.apiKey = secret "sabnzbd-api-key";
  };

  # Connection details for one *Arr, reused as the sync target base and (with a name)
  # as Prowlarr's readiness/application targets — one source of truth per app.
  arrs = lib.mapAttrs (name: a: a // { key = secretName name; }) {
    sonarr = {
      apiVersion = "v3";
      port = ports.sonarr;
    };
    radarr = {
      apiVersion = "v3";
      port = ports.radarr;
    };
    lidarr = {
      apiVersion = "v1";
      port = ports.lidarr;
    };
  };
  arrApi = a: {
    url = localUrl a.port;
    inherit (a) apiVersion;
    apiKeyFile = secret a.key;
  };

  # Register an *Arr as a Prowlarr Application (so Prowlarr pushes indexers to it).
  application = implementation: a: {
    name = implementation;
    inherit implementation;
    fields = {
      prowlarrUrl = localUrl ports.prowlarr;
      baseUrl = localUrl a.port;
    };
    secretFields.apiKey = secret a.key;
  };
in
{
  my.arrSync = {
    enable = true;
    targets = {
      sonarr = arrApi arrs.sonarr // {
        afterUnits = downloadClientUnits;
        rootFolders = [ "/mnt/hoard/plex/shows" ];
        downloadClients = [
          (qbittorrent { tvCategory = "sonarr"; })
          (sabnzbd { tvCategory = "tv"; })
        ];
      };
      radarr = arrApi arrs.radarr // {
        afterUnits = downloadClientUnits;
        rootFolders = [ "/mnt/hoard/plex/movies" ];
        downloadClients = [
          (qbittorrent { movieCategory = "radarr"; })
          (sabnzbd { movieCategory = "movies"; })
        ];
      };
      lidarr = arrApi arrs.lidarr // {
        afterUnits = downloadClientUnits;
        rootFolders = [ "/mnt/hoard/media/music" ];
        # Lidarr root folders require default quality/metadata profiles.
        rootFolderNeedsProfiles = true;
        downloadClients = [
          (qbittorrent { musicCategory = "lidarr"; })
          (sabnzbd { musicCategory = "music"; })
        ];
      };
      prowlarr = {
        url = localUrl ports.prowlarr;
        apiVersion = "v1";
        apiKeyFile = secret (secretName "prowlarr");
        afterUnits = downloadClientUnits ++ [
          config.systemd.services.sonarr.name
          config.systemd.services.radarr.name
          config.systemd.services.lidarr.name
        ];
        downloadClients = [
          (qbittorrent { category = "prowlarr"; })
          (sabnzbd { category = "prowlarr"; })
        ];
        # POSTing an Application tests the *Arr connection, so wait for them first.
        waitForTargets = lib.attrNames arrs;
        applications = [
          (application "Sonarr" arrs.sonarr)
          (application "Radarr" arrs.radarr)
          (application "Lidarr" arrs.lidarr)
        ];
      };
    };
  };
}
