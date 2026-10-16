# Radarr and Sonarr notifications, converged by my.arrSync on every start of
# the app (see modules/system/nixos/arr-sync.nix). Kept as they were set in the
# UIs on 2026-10-16: the same ids, names, events and Telegram forum topics.
#
# Every event flag is declared, so a flag ticked in the UI is unticked on the
# next start. Writes always skip Servarr's connection test, so converging
# never sends a message.
#
# The secrets were migrated from the live apps into secrets/openclaw/arr.yaml
# without rotation (the Telegram bot and group are the ones Tautulli and
# Maintainerr post with). A SOPS value differing from a live one is never
# written over it: arr-sync keeps the live value and fails, naming the field.
{ config, lib, ... }:
let
  secret = name: config.sops.secrets.${name}.path;
  secretNames = [
    "arr-telegram-bot-token"
    "arr-telegram-chat-id"
    "arr-ruddarr-webhook-url"
    "arr-ruddarr-webhook-password"
  ];

  # forum topics of the media group, as Tautulli posts to them
  topics = {
    movies = 15;
    tvShows = 16;
  };

  # every flag off but the listed ones
  events = all: on: lib.genAttrs all (event: lib.elem event on);
  radarrEvents = [
    "onGrab"
    "onDownload"
    "onUpgrade"
    "onRename"
    "onMovieAdded"
    "onMovieDelete"
    "onMovieFileDelete"
    "onMovieFileDeleteForUpgrade"
    "onHealthIssue"
    "onHealthRestored"
    "onApplicationUpdate"
    "onManualInteractionRequired"
  ];
  sonarrEvents = [
    "onGrab"
    "onDownload"
    "onImportComplete"
    "onUpgrade"
    "onRename"
    "onSeriesAdd"
    "onSeriesDelete"
    "onEpisodeFileDelete"
    "onEpisodeFileDeleteForUpgrade"
    "onHealthIssue"
    "onHealthRestored"
    "onApplicationUpdate"
    "onManualInteractionRequired"
  ];

  telegram =
    {
      name,
      allEvents,
      on,
      topic,
      metadataLinks,
    }:
    {
      id = 2;
      inherit name;
      implementation = "Telegram";
      events = events allEvents on;
      fields = {
        topicId = topics.${topic};
        sendSilently = true;
        includeAppNameInTitle = false;
        includeInstanceNameInTitle = false;
        inherit metadataLinks;
      };
      secretFields = {
        botToken = secret "arr-telegram-bot-token";
        chatId = secret "arr-telegram-chat-id";
      };
    };

  # Ruddarr's push relay (the iOS app); every event is off, so it sends nothing
  ruddarr = allEvents: {
    id = 3;
    name = "Ruddarr";
    implementation = "Webhook";
    events = events allEvents [ ];
    fields = {
      # POST
      method = 1;
      headers = [ ];
      username = "";
    };
    secretFields = {
      # the push URL embeds the device's token
      url = secret "arr-ruddarr-webhook-url";
      password = secret "arr-ruddarr-webhook-password";
    };
  };
in
{
  my.arrSync.targets = {
    radarr.notifications = [
      (telegram {
        name = "Telegram Group - Movie record deleted / Quality upgraded";
        allEvents = radarrEvents;
        on = [
          "onUpgrade"
          "onMovieDelete"
        ];
        topic = "movies";
        # IMDb (Radarr's 0 is TMDb)
        metadataLinks = [ 1 ];
      })
      (ruddarr radarrEvents)
    ];
    sonarr.notifications = [
      (telegram {
        name = "Telegram Group - (On delete)";
        allEvents = sonarrEvents;
        on = [ "onSeriesDelete" ];
        topic = "tvShows";
        # IMDb (Sonarr's 0)
        metadataLinks = [ 0 ];
      })
      (ruddarr sonarrEvents)
    ];
  };

  sops.secrets = lib.genAttrs secretNames (_: {
    sopsFile = ../../../secrets/openclaw/arr.yaml;
    restartUnits = [
      config.systemd.services.arr-sync-radarr.name
      config.systemd.services.arr-sync-sonarr.name
    ];
  });
}
