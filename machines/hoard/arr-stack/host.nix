# Radarr's and Sonarr's host settings (Settings → General), converged by
# my.arrSync through config/host. Kept as they were on 2026-10-16.
#
# One owner per key:
#   - the app's environment (services.<app>.settings from the NixOS module, and
#     ./auth.nix) wins over config.xml, so every key it sets is dropped here
#     (see envOwned): today port, analyticsEnabled, updateMechanism and
#     updateAutomatically, and authenticationMethod whenever ./auth.nix
#     delegates auth to the gateway;
#   - the rest is declared below.
# Not declared here: the API key (./auth.nix) and the login, user name and
# password, which config/host can't take as a hash (see CREDENTIAL_SETTINGS in
# arr-sync.py); ./sync.nix restores the login whole from SOPS instead. Nor
# trustCgnatIpAddresses, which config/host doesn't map: GET
# always answers false whatever is stored, so it can't be compared. It's unset
# (false) in both config.xml files. Any config/host save, here or in the UI,
# sends that false back: set it through the environment
# (services.<app>.settings.auth.trustCgnatIpAddresses) if it's ever wanted.
#
# A write here never restarts the app. The keys under "takes a restart" are
# read only at startup: a drifted value is written back to config.xml and
# applies at the app's next start. Converging an unchanged app writes nothing.
#
# Known, left as is: NixOS sets update.mechanism = "external", but Servarr
# parses that environment value case-sensitively (Enum.TryParse, wants
# "External"), so the effective mechanism is the app's default, builtIn, as
# the API reports. Changing it would change behavior and restart the apps.
{ config, lib, ... }:
let
  # config/host keys set through the app's environment: <APP>__SECTION__KEY,
  # matched case-insensitively like .NET's configuration does. Sections and
  # keys are Servarr's option classes (src/NzbDrone.Common/Options/*Options.cs);
  # the API key comes from ./auth.nix's environment file and is never declared.
  envKeys = {
    server = {
      port = "port";
      bindaddress = "bindAddress";
      urlbase = "urlBase";
      enablessl = "enableSsl";
      sslport = "sslPort";
      sslcertpath = "sslCertPath";
      sslcertpassword = "sslCertPassword";
      allowedhosts = "allowedHosts";
      trustednetworks = "trustedNetworks";
    };
    log = {
      analyticsenabled = "analyticsEnabled";
      level = "logLevel";
      consolelevel = "consoleLogLevel";
      sizelimit = "logSizeLimit";
    };
    update = {
      mechanism = "updateMechanism";
      automatically = "updateAutomatically";
      scriptpath = "updateScriptPath";
      branch = "branch";
    };
    auth = {
      method = "authenticationMethod";
      required = "authenticationRequired";
      apikey = "apiKey";
    };
    app = {
      instancename = "instanceName";
      launchbrowser = "launchBrowser";
    };
  };
  envOwned =
    app:
    lib.concatLists (
      lib.mapAttrsToList (
        section: keys:
        lib.concatLists (
          lib.mapAttrsToList (
            key: value:
            let
              hostKey = envKeys.${lib.toLower section}.${lib.toLower key} or null;
            in
            lib.optional (value != null && hostKey != null) hostKey
          ) keys
        )
      ) (lib.filterAttrs (_: lib.isAttrs) config.services.${app}.settings)
    );

  host =
    app: values:
    lib.removeAttrs (
      {
        # takes a restart
        bindAddress = "*";
        sslPort = 9898;
        enableSsl = false;
        sslCertPath = "";
        sslCertPassword = "";
        urlBase = "";
        # the service runs with -nobrowser anyway
        launchBrowser = true;
        # ./auth.nix switches the method to External behind the gateway's SSO
        authenticationMethod = "forms";
        authenticationRequired = "enabled";
        logLevel = "debug";
        consoleLogLevel = "";
        # MB per log file
        logSizeLimit = 1;
        updateScriptPath = "";
        applicationUrl = "";
        proxyEnabled = false;
        proxyType = "http";
        proxyHostname = "";
        proxyPort = 8080;
        proxyUsername = "";
        proxyPassword = "";
        proxyBypassFilter = "";
        proxyBypassLocalAddresses = true;
        certificateValidation = "enabled";
        # relative to the app's data dir; days, and backups kept
        backupFolder = "Backups";
        backupInterval = 1;
        backupRetention = 7;
      }
      // values
    ) (envOwned app);
in
{
  my.arrSync.targets = {
    radarr.settings."config/host" = host "radarr" {
      branch = "master";
      instanceName = "Radarr";
      allowedHosts = "";
      trustedNetworks = "";
    };
    sonarr.settings."config/host" = host "sonarr" {
      branch = "main";
      instanceName = "Sonarr";
    };
  };
}
