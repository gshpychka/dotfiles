{ config, lib, ... }:

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
  };

  config = lib.mkIf cfg.enable {
    # Secret containing an auth key for this machine
    sops.secrets."tailscale-auth-key" = {
      sopsFile = ../secrets/common/tailscale.yaml;
      key = "tailscale-auth-key";
      restartUnits = [ config.systemd.services.tailscaled-autoconnect.name ];
    };

    services.tailscale = {
      enable = true;
      extraUpFlags = lib.optionals cfg.ssh [ "--ssh" ];
      extraSetFlags =
        lib.optionals (!cfg.magicDns) [ "--accept-dns=false" ]
        ++ lib.optionals cfg.exitNode [ "--advertise-exit-node" ];
      authKeyFile = config.sops.secrets."tailscale-auth-key".path;
    };

    # Enable IP forwarding for exit node functionality
    boot.kernel.sysctl = lib.mkIf cfg.exitNode (
      {
        # TODO: research this, as opposed to "net.ipv4.conf.all.forwarding = 1"
        "net.ipv4.ip_forward" = true;
      }
      // lib.optionalAttrs config.networking.enableIPv6 { "net.ipv6.conf.all.forwarding" = true; }
    );

    # Configure firewall for exit node traffic
    networking.firewall = {
      extraCommands = lib.mkIf cfg.exitNode ''
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
