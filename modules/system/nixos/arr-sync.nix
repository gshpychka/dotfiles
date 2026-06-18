# Declarative cross-service wiring for the Servarr stack.
#
# Each `my.arrSync.targets.<name>` describes config to push INTO one app (an *Arr or
# Prowlarr) over its REST API: root folders, download clients, and — for Prowlarr —
# applications. A per-target systemd oneshot runs the bundled `arr-sync` engine, which
# upserts the declared resources idempotently (see arr-sync.py).
#
# Auth uses the app's API key (X-Api-Key). The oneshot runs as root so it can read the
# SOPS secret files (root:root 0400) referenced by `apiKeyFile` / `secretFields`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.arrSync;

  # ruff format owns line width, so flake8's E501 is ignored.
  engine = pkgs.writers.writePython3Bin "arr-sync" { flakeIgnore = [ "E501" ]; } (
    builtins.readFile ./arr-sync.py
  );

  # A non-secret download-client / application field value.
  fieldType = lib.types.oneOf [
    lib.types.str
    lib.types.int
    lib.types.bool
  ];

  # Secret field values are runtime file paths (e.g. a SOPS secret), read by the engine
  # at activation. Stored as strings to keep the secret out of the Nix store.
  secretFieldsType = lib.types.attrsOf lib.types.str;

  downloadClientType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name; also the identity used for idempotent upserts.";
      };
      implementation = lib.mkOption {
        type = lib.types.str;
        example = "QBittorrent";
        description = "Download-client implementation (must match a /schema entry).";
      };
      protocol = lib.mkOption {
        type = lib.types.enum [
          "torrent"
          "usenet"
        ];
      };
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      priority = lib.mkOption {
        type = lib.types.int;
        default = 1;
      };
      fields = lib.mkOption {
        type = lib.types.attrsOf fieldType;
        default = { };
        description = "Non-secret implementation fields, e.g. host/port/category.";
      };
      secretFields = lib.mkOption {
        type = secretFieldsType;
        default = { };
        description = "Implementation fields whose values are read from a file at runtime.";
      };
    };
  };

  applicationType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      implementation = lib.mkOption {
        type = lib.types.str;
        example = "Sonarr";
        description = "Prowlarr application implementation (must match a /schema entry).";
      };
      syncLevel = lib.mkOption {
        type = lib.types.enum [
          "fullSync"
          "addOnly"
          "disabled"
        ];
        default = "fullSync";
      };
      fields = lib.mkOption {
        type = lib.types.attrsOf fieldType;
        default = { };
      };
      secretFields = lib.mkOption {
        type = secretFieldsType;
        default = { };
      };
    };
  };

  targetType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
        example = "http://localhost:8989";
      };
      apiVersion = lib.mkOption {
        type = lib.types.enum [
          "v1"
          "v3"
        ];
        description = "API version: v3 for Sonarr/Radarr, v1 for Prowlarr/Lidarr.";
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to a file holding the target's API key (sent as X-Api-Key).";
      };
      afterUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra systemd units to order after (e.g. download-client services).";
      };
      rootFolders = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      rootFolderNeedsProfiles = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether root folders require default quality/metadata profiles (Lidarr).
          When set, the engine attaches the first available profiles and monitor=all.
        '';
      };
      downloadClients = lib.mkOption {
        type = lib.types.listOf downloadClientType;
        default = [ ];
      };
      applications = lib.mkOption {
        type = lib.types.listOf applicationType;
        default = [ ];
      };
      waitForTargets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Other target names whose API must be reachable before syncing (e.g. Prowlarr → *Arrs).";
      };
    };
  };

  # submodule values carry an internal _module attr; drop it before JSON serialization
  clean = x: removeAttrs x [ "_module" ];

  specFile =
    tname: t:
    (pkgs.formats.json { }).generate "arr-sync-${tname}.json" {
      name = tname;
      inherit (t)
        url
        apiVersion
        apiKeyFile
        rootFolders
        rootFolderNeedsProfiles
        ;
      downloadClients = map clean t.downloadClients;
      applications = map clean t.applications;
      waitFor = map (n: {
        name = n;
        inherit (cfg.targets.${n}) url apiVersion apiKeyFile;
      }) t.waitForTargets;
    };
in
{
  options.my.arrSync = {
    enable = lib.mkEnableOption "declarative Servarr cross-service wiring";
    targets = lib.mkOption {
      type = lib.types.attrsOf targetType;
      default = { };
      description = "Apps to push wiring into, keyed by their systemd service name.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mapAttrs' (
      tname: t:
      let
        ownUnit = config.systemd.services.${tname}.name;
      in
      lib.nameValuePair "arr-sync-${tname}" {
        description = "Converge ${tname} cross-service wiring";
        after = [ ownUnit ] ++ t.afterUnits;
        wants = [ ownUnit ];
        wantedBy = [ "multi-user.target" ];
        # Spec/engine live in the store, so a changed wiring re-runs this on switch.
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe' engine "arr-sync"} ${specFile tname t}";
          # Reads SOPS secret files; only talks to localhost APIs.
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
        };
      }
    ) cfg.targets;
  };
}
