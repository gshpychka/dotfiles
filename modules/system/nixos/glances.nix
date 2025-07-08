{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.my.glances;

  # Generate glances configuration file
  glancesConfig = pkgs.writeText "glances.conf" ''
    ${optionalString (cfg.networkInterfaces != null) ''
      [network]
      # Show only specified network interfaces
      show=${concatStringsSep "," cfg.networkInterfaces}
    ''}

    ${optionalString (cfg.filesystems != null) ''
      [fs]
      # Show only specified filesystems/mount points
      show=${concatStringsSep "," cfg.filesystems}
    ''}

    [sensors]
    # Only show CPU package temperature
    show=Package.*
  '';
in
{
  options.my.glances = {
    enable = mkEnableOption "Glances monitoring service";

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open firewall port for Glances";
    };

    networkInterfaces = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      example = [
        "eth0"
        "wlan0"
      ];
      description = "List of network interfaces to monitor. If null, all interfaces are monitored.";
    };

    filesystems = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      example = [
        "/mnt/.*"
        "/home"
        "/"
      ];
      description = "List of mount points to monitor (regex patterns). If null, all physical devices are monitored.";
    };
  };

  config = mkIf cfg.enable {
    # Enable base glances service
    services.glances = {
      enable = true;
      openFirewall = cfg.openFirewall;
      package = pkgs.glances.overrideAttrs (oldAttrs: {
        # Wrap glances to include lm_sensors in its PATH
        postInstall =
          (oldAttrs.postInstall or "")
          + ''
            wrapProgram $out/bin/glances \
              --prefix PATH : ${lib.makeBinPath [ pkgs.lm_sensors ]}
          '';
      });
      extraArgs = [
        "--webserver"
        "--disable-webui"
        "-C"
        "${glancesConfig}"
        "--disable-autodiscover"
        "--disable-check-update"
        "--disable-plugin"
        "all"
        "--enable-plugin"
        "cpu,mem,sensors,fs,network,system"
      ];
    };
  };
}

