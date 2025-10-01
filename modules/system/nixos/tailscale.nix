{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.tailscale;
in
{
  options.my.tailscale = {
    enable = lib.mkEnableOption "Tailscale integration";
    ssh = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Tailscale SSH support";
    };
    magicDns = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use MagicDNS for resolution";
    };
    exitNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise this machine as a Tailscale exit node";
    };
    advertiseRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of subnet routes to advertise";
      example = [ "192.168.1.0/24" ];
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."tailscale-auth-key" = {
      sopsFile = ../../../secrets/common/tailscale.yaml;
      key = "tailscale-auth-key";
      restartUnits = [ config.systemd.services.tailscaled-autoconnect.name ];
    };

    services.tailscale = {
      enable = true;
      extraSetFlags = [
        (if cfg.ssh then "--ssh" else "--ssh=false")
      ]
      ++ [ (if cfg.magicDns then "--accept-dns" else "--accept-dns=false") ]
      ++ [ (if cfg.exitNode then "--advertise-exit-node" else "--advertise-exit-node=false") ]
      ++ [
        "--advertise-routes"
        "${lib.concatStringsSep "," cfg.advertiseRoutes}"
      ];
      authKeyFile = config.sops.secrets."tailscale-auth-key".path;
    };

    # Enable IP forwarding for exit node functionality and subnet routing
    boot.kernel.sysctl = lib.mkIf (cfg.exitNode || cfg.advertiseRoutes != [ ]) (
      {
        # TODO: research this, as opposed to "net.ipv4.conf.all.forwarding = 1"
        "net.ipv4.ip_forward" = true;
      }
      // lib.optionalAttrs config.networking.enableIPv6 { "net.ipv6.conf.all.forwarding" = true; }
    );

    # Configure firewall for exit node traffic and subnet routing
    networking.firewall = {
      extraCommands = lib.mkIf (cfg.exitNode || cfg.advertiseRoutes != [ ]) ''
        # Allow forwarding to and from Tailscale interface
        iptables -A FORWARD -i ${config.services.tailscale.interfaceName} -j ACCEPT
        iptables -A FORWARD -o ${config.services.tailscale.interfaceName} -j ACCEPT
      '';
    };

    networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts =
      # only affects the tailscale interface
      lib.mkIf cfg.ssh [ 22 ];
  };
}
