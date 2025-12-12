{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.gatus-path-check;
  # https://github.com/TwiN/gatus/?tab=readme-ov-file#external-endpoints
  sanitize =
    str:
    builtins.replaceStrings
      [
        " "
        "/"
        "_"
        ","
        "."
        "#"
        "+"
        "&"
      ]
      [
        "-"
        "-"
        "-"
        "-"
        "-"
        "-"
        "-"
        "-"
      ]
      str;
  endpointKey = "${sanitize cfg.endpointGroup}_${sanitize cfg.endpointName}";
in
with lib;
{
  options.my.gatus-path-check = {
    enable = mkEnableOption "Gatus path readability checker";

    user = mkOption {
      type = types.str;
      description = "User to run the service as";
    };

    group = mkOption {
      type = types.str;
      description = "Group to run the service as";
    };

    endpointGroup = mkOption {
      type = types.str;
      description = "Gatus endpoint group name";
      default = "";
    };

    endpointName = mkOption {
      type = types.str;
      description = "Gatus endpoint name";
    };

    apiBaseUrl = mkOption {
      type = types.str;
      description = "Base URL of the Gatus API (without trailing slash)";
      example = "https://status.example.com";
    };

    tokenFile = mkOption {
      type = types.path;
      description = "File containing the Bearer token for Gatus API authentication";
    };

    path = mkOption {
      type = types.path;
      description = "Path to check for readability";
    };

    intervalSeconds = mkOption {
      type = types.ints.positive;
      default = 300;
      description = "Interval in seconds between health checks";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.gatus-path-check = {
      description = "Check path readability and report to Gatus";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        LoadCredential = "token:${cfg.tokenFile}";
        RequiresMountsFor = cfg.path;
      };

      script = ''
        TOKEN=$(cat "$CREDENTIALS_DIRECTORY/token")

        if [ -r "${cfg.path}" ]; then
          echo "${cfg.path} is readable"
          SUCCESS=true
        else
          echo "${cfg.path} is NOT readable"
          SUCCESS=false
        fi

        ${pkgs.curl}/bin/curl -X POST \
          -H "Authorization: Bearer $TOKEN" \
          "${cfg.apiBaseUrl}/api/v1/endpoints/${endpointKey}/external?success=$SUCCESS"

        # exit non-zero on failure
        [ "$SUCCESS" = "true" ]
      '';
    };

    systemd.timers.gatus-path-check = {
      description = "Timer for Gatus path readability checker";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "${toString cfg.intervalSeconds}s";
        Unit = config.systemd.services.gatus-path-check.serviceConfig.Unit;
      };
    };
  };
}
