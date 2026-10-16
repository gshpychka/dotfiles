# Declarative configuration for the Servarr stack.
#
# Each `my.arrSync.targets.<name>` describes config to push INTO one app (an *Arr or
# Prowlarr) over its REST API: root folders, download clients, notifications, settings
# singletons (config/naming, ...), quality definitions, fields of existing quality
# profiles and — for Prowlarr — applications. A per-target systemd oneshot runs the
# bundled `arr-sync` engine, which plans with reads only and then writes just what
# differs (see arr-sync.py for the matching and secret adoption rules).
#
# Auth uses the app's API key (X-Api-Key). The oneshot runs as root so it can read the
# SOPS secret files (root:root 0400) referenced by `apiKeyFile` / `secretFields`, and
# the app's database (read-only) to compare the secrets the API masks.
#
# Before a deploy that changes this, check it against the live apps without writing:
#   sudo arr-sync-preview <target> --expect-no-changes
# (non-zero on a problem, a secret differing from SOPS, or with the flag any write).
# Verify after a deploy: journalctl -u 'arr-sync-*' shows "converged, 0 write(s)" on a
# second start; before-images of each run that wrote are in /var/lib/arr-sync (0700).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.arrSync;

  # ruff format owns line width and line breaks, so flake8's E501 and W503 are ignored.
  linted = pkgs.writers.writePython3Bin "arr-sync" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./arr-sync.py);
  # the engine, usable only once its tests (fake Servarr API, synthetic secrets) pass
  engine =
    pkgs.runCommand "arr-sync-tested"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        meta.mainProgram = "arr-sync";
      }
      ''
        cp ${./arr-sync.py} arr_sync.py
        python3 -I ${./arr-sync-test.py} "$PWD"
        mkdir -p $out/bin
        ln -s ${lib.getExe linted} $out/bin/arr-sync
      '';

  json = (pkgs.formats.json { }).type;

  # Secret field values are runtime file paths (e.g. a SOPS secret), read by the engine
  # at activation. Stored as strings to keep the secret out of the Nix store.
  secretFieldsType = lib.types.attrsOf lib.types.str;

  idOption = lib.mkOption {
    type = lib.types.nullOr lib.types.ints.positive;
    default = null;
    description = ''
      The resource's id in the live app. It stays matched while it holds the same
      implementation, so a rename in the UI is undone instead of duplicated; a fresh
      install (other ids) falls back to matching by name.
    '';
  };

  # options shared by every provider kind
  providerOptions = {
    id = idOption;
    name = lib.mkOption {
      type = lib.types.str;
      description = "Display name; also the identity used when the id doesn't match.";
    };
    implementation = lib.mkOption {
      type = lib.types.str;
      example = "QBittorrent";
      description = "Implementation (must match a /schema entry).";
    };
    fields = lib.mkOption {
      type = lib.types.attrsOf json;
      default = { };
      description = "Non-secret implementation fields, e.g. host/port/category.";
    };
    secretFields = lib.mkOption {
      type = secretFieldsType;
      default = { };
      description = "Implementation fields whose values are read from a file at runtime.";
    };
  };

  downloadClientType = lib.types.submodule {
    options = providerOptions // {
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
      # null leaves the app's value alone (Prowlarr has no such settings)
      removeCompletedDownloads = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
      };
      removeFailedDownloads = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
      };
      tags = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.int);
        default = null;
      };
    };
  };

  notificationType = lib.types.submodule {
    options = providerOptions // {
      events = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        default = { };
        example = {
          onGrab = false;
          onUpgrade = true;
        };
        description = ''
          The notification's event flags (onGrab, onUpgrade, ...). Declare every flag of
          the implementation: an undeclared one is left as it is.
        '';
      };
      includeHealthWarnings = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      tags = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
      };
    };
  };

  applicationType = lib.types.submodule {
    options = providerOptions // {
      syncLevel = lib.mkOption {
        type = lib.types.enum [
          "fullSync"
          "addOnly"
          "disabled"
        ];
        default = "fullSync";
      };
    };
  };

  # sizes in MB per minute; null is no limit
  qualityDefinitionType = lib.types.submodule {
    options = {
      title = lib.mkOption { type = lib.types.str; };
      minSize = lib.mkOption { type = lib.types.number; };
      preferredSize = lib.mkOption { type = lib.types.nullOr lib.types.number; };
      maxSize = lib.mkOption { type = lib.types.nullOr lib.types.number; };
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
      database = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The app's SQLite database, opened read-only to compare secret fields the API
          masks. Without it a masked secret can't be checked and is left as it is.
        '';
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
      notifications = lib.mkOption {
        type = lib.types.listOf notificationType;
        default = [ ];
      };
      applications = lib.mkOption {
        type = lib.types.listOf applicationType;
        default = [ ];
      };
      settings = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf json);
        default = { };
        example = {
          "config/naming".renameMovies = true;
        };
        description = ''
          Settings singletons keyed by their API path (GET returns one object with an
          id): only the listed keys are compared and written.
        '';
      };
      qualityDefinitions = lib.mkOption {
        type = lib.types.attrsOf qualityDefinitionType;
        default = { };
        description = "Quality sizes keyed by quality name; undeclared qualities are left alone.";
      };
      qualityProfiles = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf json);
        default = { };
        description = ''
          Fields of existing quality profiles keyed by profile name. Profiles are never
          created here, so another owner (Recyclarr) keeps their qualities and scores.
        '';
      };
      waitForTargets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Other target names whose API must be reachable before syncing (e.g. Prowlarr → *Arrs).";
      };
    };
  };

  # the engine's provider shape: top-level properties apart from fields
  provider =
    extraProperties: p:
    {
      inherit (p)
        name
        implementation
        fields
        secretFields
        ;
      properties = lib.filterAttrs (_: v: v != null) (extraProperties p);
    }
    // lib.optionalAttrs (p.id != null) { inherit (p) id; };

  specFile =
    tname: t:
    (pkgs.formats.json { }).generate "arr-sync-${tname}.json" {
      name = tname;
      inherit (t)
        url
        apiVersion
        apiKeyFile
        database
        rootFolders
        rootFolderNeedsProfiles
        settings
        qualityDefinitions
        qualityProfiles
        ;
      downloadClients = map (provider (p: {
        inherit (p)
          enable
          priority
          protocol
          removeCompletedDownloads
          removeFailedDownloads
          tags
          ;
      })) t.downloadClients;
      notifications = map (provider (
        p:
        p.events
        // {
          inherit (p) includeHealthWarnings tags;
        }
      )) t.notifications;
      applications = map (provider (p: {
        inherit (p) syncLevel;
      })) t.applications;
      waitFor = map (n: {
        name = n;
        inherit (cfg.targets.${n}) url apiVersion apiKeyFile;
      }) t.waitForTargets;
    };

  backupDir = "/var/lib/arr-sync";

  preview = pkgs.writeShellApplication {
    name = "arr-sync-preview";
    text = ''
      # usage: arr-sync-preview <target> [--expect-no-changes]; GET requests only
      case "''${1:-}" in
      ${lib.concatStrings (
        lib.mapAttrsToList (tname: t: ''
          ${tname}) spec=${specFile tname t} ;;
        '') cfg.targets
      )}
      *) echo "usage: arr-sync-preview <${lib.concatStringsSep "|" (lib.attrNames cfg.targets)}> [--expect-no-changes]" >&2; exit 2 ;;
      esac
      shift
      exec ${lib.getExe engine} preview "$spec" "$@"
    '';
  };
in
{
  options.my.arrSync = {
    enable = lib.mkEnableOption "declarative Servarr configuration";
    targets = lib.mkOption {
      type = lib.types.attrsOf targetType;
      default = { };
      description = "Apps to push configuration into, keyed by their systemd service name.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ preview ];

    systemd.services = lib.mapAttrs' (
      tname: t:
      let
        ownUnit = config.systemd.services.${tname}.name;
      in
      lib.nameValuePair "arr-sync-${tname}" {
        description = "Converge ${tname} configuration";
        after = [ ownUnit ] ++ t.afterUnits;
        # converges only while the app runs, and again each time it (re)starts:
        # partOf stops this with the app, so the app's next start runs it again
        wantedBy = [
          "multi-user.target"
          ownUnit
        ];
        partOf = [ ownUnit ];
        # Spec/engine live in the store, so a changed configuration re-runs this on switch.
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecCondition = "${lib.getExe' pkgs.systemd "systemctl"} is-active --quiet ${ownUnit}";
          ExecStart = "${lib.getExe engine} apply ${specFile tname t} ${backupDir}";
          # before-images hold settings as the API returns them: root only
          StateDirectory = "arr-sync";
          StateDirectoryMode = "0700";
          UMask = "0077";
          # Reads SOPS secret files and the app's database; only talks to localhost APIs.
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
        };
      }
    ) cfg.targets;
  };
}
