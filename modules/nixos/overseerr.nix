# https://github.com/NixOS/nixpkgs/pull/399266
{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.overseerr;
in
{
  meta.maintainers = [ lib.maintainers.jf-uu ];

  options.services.overseerr = {
    enable = lib.mkEnableOption "Overseerr, a request management and media discovery tool for the Plex ecosystem";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open a port in the firewall for the Overseerr web interface.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5055;
      description = "The port which the Overseerr web UI should listen on.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/overseerr";
      description = "The directory where Overseerr stores its data files.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "overseerr";
      description = "User account under which Overseerr runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "overseerr";
      description = "Group under which Overseerr runs.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      # https://github.com/NixOS/nixpkgs/pull/399266
      (
        final: prev:
        let
          overseerrPkgs = import inputs.overseerr-nixpkgs {
            inherit (final) system config;
          };
        in
        {
          overseerr = overseerrPkgs.overseerr;
        }
      )
    ];
    systemd.services.overseerr = {
      description = "Request management and media discovery tool for the Plex ecosystem";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        CONFIG_DIRECTORY = cfg.dataDir;
        PORT = toString cfg.port;
      };
      serviceConfig = {
        Type = "exec";
        WorkingDirectory = "${pkgs.overseerr}/libexec/overseerr/deps/overseerr";
        ExecStart = lib.getExe pkgs.overseerr;
        Restart = "on-failure";
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        PrivateMounts = true;
        ReadWritePaths = [ cfg.dataDir ];
        StateDirectory = lib.mkIf (cfg.dataDir == "/var/lib/overseerr") "overseerr";
        StateDirectoryMode = "0700";
        DynamicUser = cfg.user == "overseerr" && cfg.group == "overseerr";
        User = cfg.user;
        Group = cfg.group;
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
