{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.my.disk-spindown;

  # Convert timeout in minutes to hdparm -S flag value
  # https://man.archlinux.org/man/hdparm.8#S
  # - Value 0: disable spindown
  # - Values 1-240: multiples of 5 seconds (5s to 20 minutes)
  # - Values 241-251: multiples of 30 minutes (30min to 330min/5.5h)
  # - Value 253: vendor-defined (~21 minutes 15 seconds)
  minutesToHdparmValue =
    minutes:
    if minutes == 0 then
      0 # Disable spindown
    else if minutes >= 1 && minutes <= 20 then
      # For 1-20 minutes: convert to 5-second units
      # 1 minute = 60 seconds = 12 five-second units
      minutes * 12
    else if minutes >= 30 && minutes <= 330 && (mod minutes 30 == 0) then
      # For 30-330 minutes: convert to 30-minute units, offset by 240
      # 241 = 30min, 242 = 60min, ..., 251 = 330min
      (minutes / 30) + 240
    else
      throw "Invalid timeoutMinutes value: ${toString minutes}. Must be 0 (disable), 1-20 (minutes), or 30-330 (in 30-minute increments).";

  # Validate that timeout is in a supported range
  isValidTimeout =
    minutes:
    minutes == 0
    || (minutes >= 1 && minutes <= 20)
    || (minutes >= 30 && minutes <= 330 && (mod minutes 30 == 0));

  # Custom type with validation and error message
  timeoutType = types.mkOptionType {
    name = "timeoutMinutes";
    description = "valid hdparm timeout in minutes";
    check = isValidTimeout;
    descriptionClass = "noun";
    merge = lib.mergeEqualOption;
  };
in
{
  options.my.disk-spindown = {
    enable = mkEnableOption "disk spindown configuration";

    devices = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "/dev/sdd"
        "/dev/disk/by-label/foo"
      ];
      description = "List of device paths to configure for spindown";
    };

    timeoutMinutes = mkOption {
      type = timeoutType;
      default = 5;
      example = 5;
      description = ''
        Spindown timeout in minutes.

        Valid values:
        - 0,1-20,30,60,90,...,330
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services = listToAttrs (
      map (
        device:
        let
          serviceName = builtins.replaceStrings [ "/" "-" ] [ "-" "--" ] (lib.removePrefix "/" device);
          hdparmValue = minutesToHdparmValue cfg.timeoutMinutes;
        in
        {
          name = "hdparm-${serviceName}";
          value = {
            description = "Configure hdparm for ${device}";
            wantedBy = [ "multi-user.target" ];
            after = [ "${builtins.replaceStrings [ "/" "-" ] [ "\\x2f" "\\x2d" ] device}.device" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${lib.getExe' pkgs.hdparm "hdparm"} -S ${toString hdparmValue} ${device}";
            };
          };
        }
      ) cfg.devices
    );
  };
}
