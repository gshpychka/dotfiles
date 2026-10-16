# Radarr's import lists, converged by my.arrSync (modules/system/nixos/arr-sync.nix)
# on every start of the app. Kept as they were set in the UI on 2026-10-16: the
# same ids, names, switches, targets and tags; the two Plex lists stay disabled.
#
# References are declared by logical identity, so a fresh install resolves them:
# the quality profile by name (Recyclarr creates "Any"; until then the lists are
# skipped), the root folder by path (./sync.nix adds it) and tags by label. A
# missing tag is created and never deleted. The labels are Seerr's: it tags each
# request "<user id>-<name>" and finds its tag by the "<user id>-" prefix, so it
# reuses one created here; arr-sync leaves every other tag alone.
#
# Converging never fetches a list, syncs or searches. Radarr syncs an enabled
# list as soon as it is saved (and adds and searches with auto-add), so arr-sync
# never saves one that ends up enabled: on a fresh install "Eminem" is created
# switched off and the run fails, asking for it to be switched on in the UI; a
# change to it is likewise held, not written. The disabled Plex lists are
# converged as usual. Adopting the lists as they are writes nothing.
#
# The Plex token and the watchlist RSS URL (it embeds the feed's private id) were
# copied from the live lists into secrets/openclaw/arr.yaml without rotation. The
# token isn't the shared plex-token or Tautulli's. Both are plain fields in the API;
# a SOPS value differing from the live one is never written over it (the run fails,
# naming the field).
#
# Sonarr has no import lists. arr-sync never deletes, so one added in Sonarr's UI is
# left alone until declared here.
{ config, lib, ... }:
let
  secret = name: config.sops.secrets.${name}.path;
  secretNames = [
    "arr-radarr-plex-watchlist-token"
    "arr-radarr-plex-watchlist-rss-url"
  ];

  # what each list adds, as set in the UI
  movies = rootFolderPath: {
    monitor = "movieOnly";
    searchOnAdd = true;
    minimumAvailability = "released";
    inherit rootFolderPath;
  };
in
{
  my.arrSync.targets.sonarr.importLists = [ ];

  my.arrSync.targets.radarr.importLists = [
    {
      id = 3;
      name = "Eminem";
      implementation = "TMDbPersonImport";
      properties = movies "/mnt/hoard/plex/misc" // {
        enabled = true;
        enableAuto = true;
      };
      qualityProfile = "Any";
      tags = [ "1-glibundira" ];
      fields = {
        personId = "325";
        personCast = true;
        personCastDirector = true;
        personCastProducer = true;
        personCastSound = false;
        personCastWriting = true;
      };
    }
    {
      id = 1;
      name = "Plex Watchlist";
      implementation = "PlexImport";
      properties = movies "/mnt/hoard/plex/movies" // {
        enabled = false;
        enableAuto = false;
      };
      qualityProfile = "Any";
      tags = [ "my-plex-watchlist" ];
      # the UI's "Authenticate with Plex.tv" button
      fields.signIn = "startOAuth";
      secretFields.accessToken = secret "arr-radarr-plex-watchlist-token";
    }
    {
      id = 2;
      name = "Plex Watchlist RSS";
      implementation = "PlexRssImport";
      properties = movies "/mnt/hoard/plex/movies" // {
        enabled = false;
        enableAuto = false;
      };
      qualityProfile = "Any";
      tags = [ "plex-watchlist" ];
      secretFields.url = secret "arr-radarr-plex-watchlist-rss-url";
    }
  ];

  sops.secrets = lib.genAttrs secretNames (_: {
    sopsFile = ../../../secrets/openclaw/arr.yaml;
    restartUnits = [ config.systemd.services.arr-sync-radarr.name ];
  });
}
