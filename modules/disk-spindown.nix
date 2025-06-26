{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.my.disk-spindown;
in {
  options.my.disk-spindown = {
    enable = mkEnableOption "disk spindown configuration";

    devices = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["/dev/sdd" "/dev/disk/by-label/foo"];
      description = "List of device paths to configure for spindown";
    };

    timeoutMinutes = mkOption {
      type = types.int;
      default = 5;
      example = 5;
      description = "Spindown timeout in minutes";
    };
  };

  config = mkIf cfg.enable {
    systemd.services = listToAttrs (map (device: let
      serviceName = builtins.replaceStrings ["/" "-"] ["-" "--"] (lib.removePrefix "/" device);
    in {
      name = "hdparm-${serviceName}";
      value = {
        description = "Configure hdparm for ${device}";
        wantedBy = ["multi-user.target"];
        after = ["${builtins.replaceStrings ["/" "-"] ["\\x2f" "\\x2d"] device}.device"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe' pkgs.hdparm "hdparm"} -S ${toString (cfg.timeoutMinutes * 12)} ${device}";
        };
      };
    }) cfg.devices);
  };
}