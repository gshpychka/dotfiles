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
  # service/env-prefix (lowercase) -> SOPS secret holding its API key.
  # Secrets are declared in ../monitoring.nix.
  arrKeys = {
    sonarr = "sonarr-api-key";
    radarr = "radarr-api-key";
    lidarr = "lidarr-api-key";
    prowlarr = "prowlarr-api-key";
  };
  envFileName = app: "${app}-api-key.env";
in
{
  sops.templates = lib.mapAttrs' (
    app: secret:
    lib.nameValuePair (envFileName app) {
      content = "${lib.toUpper app}__AUTH__APIKEY=${config.sops.placeholder.${secret}}\n";
      restartUnits = [ "${app}.service" ];
    }
  ) arrKeys;

  services = lib.mapAttrs (app: _: {
    environmentFiles = [ config.sops.templates.${envFileName app}.path ];
  }) arrKeys;
}
