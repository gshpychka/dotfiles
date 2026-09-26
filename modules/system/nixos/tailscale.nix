{
  config,
  lib,
  ...
}:

let
  cfg = config.my.tailscale;
in
{
  options.my.tailscale = {
    enable = lib.mkEnableOption "Tailscale integration";
    authKeySopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        sops file holding this host's own single-use auth key under
        `tailscale-auth-key` (null = the host is enrolled already).
      '';
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
    sops.secrets = lib.optionalAttrs (cfg.authKeySopsFile != null) {
      "tailscale-auth-key" = {
        sopsFile = cfg.authKeySopsFile;
        key = "tailscale-auth-key";
        restartUnits = [ config.systemd.services.tailscaled-autoconnect.name ];
      };
    };

    services.tailscale = {
      enable = true;
      openFirewall = true;
      extraSetFlags = [
        (if cfg.magicDns then "--accept-dns" else "--accept-dns=false")
      ]
      ++ [ (if cfg.exitNode then "--advertise-exit-node" else "--advertise-exit-node=false") ]
      ++ [
        "--advertise-routes"
        "${lib.concatStringsSep "," cfg.advertiseRoutes}"
      ];
      authKeyFile =
        if cfg.authKeySopsFile != null then config.sops.secrets."tailscale-auth-key".path else null;
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
  };
}
