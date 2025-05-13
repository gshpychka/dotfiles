{ config, lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
  cfg = config.services.overseerr;
in
{
  options.services.overseerr = {
    enable = mkEnableOption "Overseerr request & discovery server";

    image = mkOption {
      type = types.str;
      # default = "sctx/overseerr:07dc8d755a0e94d100ecd8b1e950e43da1c0a7dd";
      default = "sctx/overseerr:latest";
      description = "Docker image (tag) to run.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/overseerr";
      description = "/app/config bind‑mount for persistent data.";
    };

    port = mkOption {
      type = types.port;
      default = 5055;
      description = "Host TCP port for the web UI.";
    };
  };

  config = mkIf cfg.enable {

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
    ];

    virtualisation.oci-containers.containers.overseerr = {
      image = cfg.image;
      ports = [ "${toString cfg.port}:5055" ];
      volumes = [ "${cfg.dataDir}:/config" ];
      environment = {
        TZ = config.time.timeZone or "Etc/UTC";
      };
      # extraOptions = [ "--pull=always" ];
      restart = "unless-stopped";
    };
  };
}
