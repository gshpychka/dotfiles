# Auth configuration for each *Arr, pinned through `<APP>__SECTION__KEY`
# environment variables (https://wiki.servarr.com/useful-tools#using-environment-variables-for-config).
#
# The API key (`<APP>__AUTH__APIKEY`) travels through `environmentFiles` (a systemd
# EnvironmentFile), which keeps the secret out of the world-readable Nix store.
# These are the same SOPS secrets read by Recyclarr, the Homepage dashboard, and
# arr-sync, making the pinned keys reproducible from a clean install and the single
# source of truth shared across every consumer.
#
# `auth.method = "External"` turns the login form off when that app delegates
# auth to the enabled web gateway; /api keeps requiring X-Api-Key.
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
  gateway = config.my.webGateway;
  delegatesAuth =
    app:
    gateway.enable
    && gateway.sso.enable
    && builtins.hasAttr app gateway.services
    && gateway.services.${app}.auth == "gateway";
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
    settings.auth.method = lib.mkIf (delegatesAuth app) "External";
  });
}
