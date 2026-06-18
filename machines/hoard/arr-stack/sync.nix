# Declarative cross-service wiring for hoard's *Arr stack (mechanism: my.arrSync, in
# modules/system/nixos/arr-sync.nix). Converges, over each app's REST API:
#   - Prowlarr Applications  -> registers Sonarr/Radarr/Lidarr for indexer push
#   - download clients       -> qBittorrent + SABnzbd in each *Arr
#   - root folders           -> the media library path per *Arr
#
# API keys come from the SOPS secrets pinned in ./api-keys.nix, so this wiring is plain
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
  localUrl = port: "http://localhost:${port}";
  publicHost = service: "${service}.${config.networking.fqdn}";
  httpsPort = config.services.nginx.defaultSSLListenPort;

  # qBittorrent / SABnzbd are shared by every *Arr; only the per-arr category field
  # (tvCategory / movieCategory / musicCategory) differs, passed in via `category`.
  qbittorrent = category: {
    name = "qBittorrent";
    implementation = "QBittorrent";
    protocol = "torrent";
    fields = {
      host = publicHost "qbittorrent";
      port = httpsPort;
      useSsl = true;
    }
    // category;
    secretFields = {
      username = secret "qbittorrent-username";
      password = secret "qbittorrent-password";
    };
  };

  sabnzbd = category: {
    name = "SABnzbd";
    implementation = "Sabnzbd";
    protocol = "usenet";
    fields = {
      host = publicHost "sabnzbd";
      port = httpsPort;
      useSsl = true;
    }
    // category;
    secretFields.apiKey = secret "sabnzbd-api-key";
  };

  downloadClients = category: [
    (qbittorrent category)
    (sabnzbd category)
  ];

  # Connection details for one *Arr, reused as the sync target base and (with a name)
  # as Prowlarr's readiness/application targets — one source of truth per app.
  arrs = {
    sonarr = {
      apiVersion = "v3";
      port = ports.sonarr;
      key = "sonarr-api-key";
    };
    radarr = {
      apiVersion = "v3";
      port = ports.radarr;
      key = "radarr-api-key";
    };
    lidarr = {
      apiVersion = "v1";
      port = ports.lidarr;
      key = "lidarr-api-key";
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
        afterUnits = [
          "qbittorrent"
          "sabnzbd"
        ];
        rootFolders = [ "/mnt/hoard/plex/shows" ];
        downloadClients = downloadClients { tvCategory = "sonarr"; };
      };
      radarr = arrApi arrs.radarr // {
        afterUnits = [
          "qbittorrent"
          "sabnzbd"
        ];
        rootFolders = [ "/mnt/hoard/plex/movies" ];
        downloadClients = downloadClients { movieCategory = "radarr"; };
      };
      lidarr = arrApi arrs.lidarr // {
        afterUnits = [
          "qbittorrent"
          "sabnzbd"
        ];
        rootFolders = [ "/mnt/hoard/media/music" ];
        # Lidarr root folders require default quality/metadata profiles.
        rootFolderNeedsProfiles = true;
        downloadClients = downloadClients { musicCategory = "lidarr"; };
      };
      prowlarr = {
        url = localUrl ports.prowlarr;
        apiVersion = "v1";
        apiKeyFile = secret "prowlarr-api-key";
        afterUnits = [
          "sonarr"
          "radarr"
          "lidarr"
        ];
        # POSTing an Application tests the *Arr connection, so wait for them first.
        waitFor = lib.mapAttrsToList (name: a: arrApi a // { inherit name; }) arrs;
        applications = [
          (application "Sonarr" arrs.sonarr)
          (application "Radarr" arrs.radarr)
          (application "Lidarr" arrs.lidarr)
        ];
      };
    };
  };
}
