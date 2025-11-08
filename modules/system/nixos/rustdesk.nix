{
  config,
  lib,
  ...
}:

let
  cfg = config.my.rustdesk-server;

  # https://github.com/NixOS/nixpkgs/blob/ae814fd3904b621d8ab97418f1d0f2eb0d3716f4/nixos/modules/services/monitoring/rustdesk-server.nix#L6:L15
  TCPPorts = [
    21115
    21116
    21117
    21118
    21119
  ];
  UDPPorts = [ 21116 ];
in
{
  options.my.rustdesk-server = {
    enable = lib.mkEnableOption "RustDesk server";

    relayHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Relay server IP addresses or DNS names";
      example = [ "100.x.x.x" ];
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to private key file (managed via sops)";
    };

    tailscaleOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Only allow connections via Tailscale interface";
    };
  };

  config = lib.mkIf cfg.enable {
    services.rustdesk-server = {
      enable = true;
      openFirewall = false;
      signal = {
        enable = true;
        relayHosts = cfg.relayHosts;
        extraArgs = lib.optionals (cfg.privateKeyFile != null) [
          "-k"
          cfg.privateKeyFile
        ];
      };
      relay = {
        enable = true;
        extraArgs = lib.optionals (cfg.privateKeyFile != null) [
          "-k"
          cfg.privateKeyFile
        ];
      };
    };

    # Custom firewall configuration
    networking.firewall = lib.mkMerge [
      (lib.mkIf (!cfg.tailscaleOnly) {
        allowedTCPPorts = TCPPorts;
        allowedUDPPorts = UDPPorts;
      })
      (lib.mkIf cfg.tailscaleOnly {
        interfaces.${config.services.tailscale.interfaceName} = {
          allowedTCPPorts = TCPPorts;
          allowedUDPPorts = UDPPorts;
        };
      })
    ];
  };
}
