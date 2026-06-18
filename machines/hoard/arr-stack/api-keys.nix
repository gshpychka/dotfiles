# Pin each *Arr's API key from SOPS.
#
# Servarr reads config from `<APP>__SECTION__KEY` environment variables; the API key is
# `<APP>__AUTH__APIKEY`. It travels through `environmentFiles` (a systemd
# EnvironmentFile), which keeps the secret out of the world-readable Nix store.
#
# These are the same SOPS secrets read by Recyclarr, the Homepage dashboard, and
# arr-sync, making the pinned keys reproducible from a clean install and the single
# source of truth shared across every consumer.
{
  config,
  lib,
  ...
}:
let
  arrs = [
    "sonarr"
    "radarr"
    "lidarr"
    "prowlarr"
  ];
  # TODO: secretName is duplicated in sync.nix and recyclarr.nix; consolidate to one shared definition.
  secretName = service: "${service}-api-key";
  envFileName = service: "${secretName service}.env";
in
{
  sops.secrets = lib.genAttrs (map secretName arrs) (_: { });

  sops.templates = lib.listToAttrs (
    map (
      app:
      lib.nameValuePair (envFileName app) {
        content = "${lib.toUpper app}__AUTH__APIKEY=${config.sops.placeholder.${secretName app}}\n";
        restartUnits = [ config.systemd.services.${app}.name ];
      }
    ) arrs
  );

  services = lib.genAttrs arrs (app: {
    environmentFiles = [ config.sops.templates.${envFileName app}.path ];
  });
}
