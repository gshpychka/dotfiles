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
        StateDirectory = "overseerr";
        StateDirectoryMode = "0700";
        DynamicUser = true;
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
