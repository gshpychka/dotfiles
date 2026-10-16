# Declarative cross-service wiring for hoard's *Arr stack (mechanism: my.arrSync, in
# modules/system/nixos/arr-sync.nix). Converges, over each app's REST API:
#   - Prowlarr Applications  -> registers Sonarr/Radarr/Lidarr for indexer push
#   - download clients       -> qBittorrent + SABnzbd in every app (plus Radarr's and
#                               Sonarr's disabled legacy NZBGet)
#   - root folders           -> the media library paths per *Arr
#
# API keys come from the SOPS secrets pinned in ./auth.nix, so this wiring is plain
# Nix. Resources are matched by id or name (clients/apps) or path (root folders):
# existing matches are updated in place, missing ones are created, and all others are
# preserved. Radarr's and Sonarr's clients declare every setting they have in the UI.
{
  config,
  lib,
  ...
}:
let
  inherit (import ../ports.nix { inherit config; }) ports;

  secret = name: config.sops.secrets.${name}.path;
  secretName = service: "${service}-api-key";
  database = service: file: "${config.services.${service}.dataDir}/${file}";
  # migrated from the live clients into secrets/openclaw/arr.yaml
  arrSecrets = [
    "arr-sabnzbd-username"
    "arr-sabnzbd-password"
    "arr-nzbget-username"
    "arr-nzbget-password"
  ];
  # The UI login (Settings → General → Security, forms auth) of Radarr and Sonarr,
  # restored on a fresh install by my.arrSync's arr-login-<app>. Copied on 2026-10-16
  # from each app's Users row (user name, PBKDF2 hash, salt, iterations, identifier),
  # unchanged: the password itself is in no file. To change the password, change it in
  # the UI, then copy the new row into SOPS (until then every arr-sync-<app> run fails,
  # naming the differing keys; the login is never written over), without the value
  # passing through argv or the terminal, e.g. for Radarr (sqlite3 from nixpkgs#sqlite):
  #   sudo sqlite3 -readonly -json /var/lib/radarr/.config/Radarr/radarr.db \
  #     "SELECT Identifier AS identifier, Username AS username, Password AS password,
  #             Salt AS salt, Iterations AS iterations FROM Users" \
  #     | jq -c '.[0] | tojson' | sops set --value-stdin secrets/openclaw/arr.yaml '["arr-radarr-login"]'
  # A fresh install takes one restart of the app after its first start (see arr-login
  # in modules/system/nixos/arr-sync.nix).
  loginSecret = app: "arr-${app}-login";
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

  # The remaining settings of Radarr's and Sonarr's clients, as set in their UIs.
  # `media` names the app's fields: movie* for Radarr, tv* for Sonarr.
  everySetting = media: {
    removeCompletedDownloads = true;
    removeFailedDownloads = true;
    tags = [ ];
    fields."${media}ImportedCategory" = null;
  };
  priorities =
    media: value:
    let
      Media =
        {
          movie = "Movie";
          tv = "Tv";
        }
        .${media};
    in
    {
      "recent${Media}Priority" = value;
      "older${Media}Priority" = value;
    };
  qbittorrentFull =
    media: category:
    lib.recursiveUpdate (qbittorrent category) (
      lib.recursiveUpdate (everySetting media) {
        id = 1;
        fields = priorities media 0 // {
          urlBase = null;
          # qBittorrent 5's API key login, unused: username/password instead
          apiKey = null;
          # started, not forced or paused
          initialState = 0;
          sequentialOrder = false;
          firstAndLast = false;
          # the torrent's own layout
          contentLayout = 0;
        };
      }
    );
  sabnzbdFull =
    media: category:
    lib.recursiveUpdate (sabnzbd category) {
      id = 4;
      removeCompletedDownloads = true;
      removeFailedDownloads = true;
      tags = [ ];
      # -100 is SABnzbd's "Default" priority
      fields = priorities media (-100) // {
        urlBase = null;
      };
      secretFields = {
        username = secret "arr-sabnzbd-username";
        password = secret "arr-sabnzbd-password";
      };
    };
  # NZBGet was replaced by SABnzbd; its client stays, disabled, as it was
  nzbget =
    {
      media,
      priority,
      host,
      category,
    }:
    {
      id = 3;
      name = "NZBGet";
      implementation = "Nzbget";
      protocol = "usenet";
      enable = false;
      inherit priority;
      removeCompletedDownloads = true;
      removeFailedDownloads = true;
      tags = [ ];
      fields = priorities media 0 // {
        inherit host;
        port = 6789;
        useSsl = false;
        urlBase = null;
        addPaused = false;
        "${media}Category" = category;
      };
      secretFields = {
        username = secret "arr-nzbget-username";
        password = secret "arr-nzbget-password";
      };
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
  sops.secrets =
    lib.genAttrs arrSecrets (_: {
      sopsFile = ../../../secrets/openclaw/arr.yaml;
      restartUnits = [
        config.systemd.services.arr-sync-radarr.name
        config.systemd.services.arr-sync-sonarr.name
      ];
    })
    // lib.listToAttrs (
      map
        (
          app:
          lib.nameValuePair (loginSecret app) {
            sopsFile = ../../../secrets/openclaw/arr.yaml;
            # a changed secret is compared again; it's restored only into an app without a login
            restartUnits = [ config.systemd.services."arr-sync-${app}".name ];
          }
        )
        [
          "radarr"
          "sonarr"
        ]
    );

  my.arrSync = {
    enable = true;
    targets = {
      sonarr = arrApi arrs.sonarr // {
        database = database "sonarr" "sonarr.db";
        login = secret (loginSecret "sonarr");
        afterUnits = downloadClientUnits;
        rootFolders = [ "/mnt/hoard/plex/shows" ];
        downloadClients = [
          (qbittorrentFull "tv" { tvCategory = "sonarr"; })
          (sabnzbdFull "tv" { tvCategory = "tv"; })
          (nzbget {
            media = "tv";
            priority = 2;
            host = "localhost";
            category = "tv";
          })
        ];
      };
      radarr = arrApi arrs.radarr // {
        database = database "radarr" "radarr.db";
        login = secret (loginSecret "radarr");
        afterUnits = downloadClientUnits;
        rootFolders = [
          "/mnt/hoard/plex/movies"
          # concert films and specials, fed by the TMDb person import list
          "/mnt/hoard/plex/misc"
        ];
        downloadClients = [
          (qbittorrentFull "movie" { movieCategory = "radarr"; })
          (sabnzbdFull "movie" { movieCategory = "movies"; })
          (nzbget {
            media = "movie";
            priority = 3;
            host = "127.0.0.1";
            category = "movies";
          })
        ];
      };
      lidarr = arrApi arrs.lidarr // {
        database = database "lidarr" "lidarr.db";
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
        database = database "prowlarr" "prowlarr.db";
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
