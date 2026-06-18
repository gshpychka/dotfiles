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

  # Lint with ruff and byte-compile at build time; install with a patched interpreter.
  engine =
    pkgs.runCommandLocal "arr-sync"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.ruff
        ];
        meta.mainProgram = "arr-sync";
      }
      ''
        cp ${./arr-sync.py} arr-sync.py
        ruff check --config ${./ruff.toml} arr-sync.py
        python3 -m py_compile arr-sync.py
        install -Dm755 arr-sync.py $out/bin/arr-sync
        patchShebangs $out/bin/arr-sync
      '';

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

  endpointType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      url = lib.mkOption { type = lib.types.str; };
      apiVersion = lib.mkOption {
        type = lib.types.enum [
          "v1"
          "v3"
        ];
      };
      apiKeyFile = lib.mkOption { type = lib.types.str; };
    };
  };

  targetType = lib.types.submodule (
    { name, ... }:
    {
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
        serviceName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "systemd service the sync orders after (defaults to the attr name).";
        };
        afterUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra systemd services to order after (e.g. download clients).";
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
        waitFor = lib.mkOption {
          type = lib.types.listOf endpointType;
          default = [ ];
          description = "Apps whose API must be reachable before syncing (e.g. Prowlarr → *Arrs).";
        };
      };
    }
  );

  specFile =
    tname: t:
    pkgs.writeText "arr-sync-${tname}.json" (
      builtins.toJSON {
        name = tname;
        inherit (t)
          url
          apiVersion
          apiKeyFile
          rootFolders
          rootFolderNeedsProfiles
          ;
        downloadClients = map (c: {
          inherit (c)
            name
            implementation
            protocol
            enable
            priority
            fields
            secretFields
            ;
        }) t.downloadClients;
        applications = map (a: {
          inherit (a)
            name
            implementation
            syncLevel
            fields
            secretFields
            ;
        }) t.applications;
        waitFor = map (w: {
          inherit (w)
            name
            url
            apiVersion
            apiKeyFile
            ;
        }) t.waitFor;
      }
    );
in
{
  options.my.arrSync = {
    enable = lib.mkEnableOption "declarative Servarr cross-service wiring";
    targets = lib.mkOption {
      type = lib.types.attrsOf targetType;
      default = { };
      description = "Apps to push wiring into, keyed by a systemd-friendly name.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mapAttrs' (
      tname: t:
      lib.nameValuePair "arr-sync-${tname}" {
        description = "Converge ${tname} cross-service wiring";
        after = [ "${t.serviceName}.service" ] ++ map (u: "${u}.service") t.afterUnits;
        wants = [ "${t.serviceName}.service" ];
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
