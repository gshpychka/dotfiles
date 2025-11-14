{ config, ... }:
let
  secondaryWanInterface = "enp0s20f0u4";
  secondaryWanIP = "109.86.45.81";
  secondaryWanGateway = "109.86.45.254";
in
{
  networking = {
    hostName = "hoard";
    usePredictableInterfaceNames = true;
    enableIPv6 = false;
    useNetworkd = true;
    useDHCP = false;
    firewall = {
      logRefusedConnections = false;
    };
  };

  systemd.network = {
    enable = true;

    config = {
      addRouteTablesToIPRoute2 = true;
      routeTables = {
        secondary_wan = 100;
      };
    };

    # Primary LAN interface
    networks."primary" = {
      matchConfig.Name = "enp1s0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
    };

    links."primary-lan" = {
      matchConfig.Name = config.systemd.network.networks.primary.matchConfig.Name;
      linkConfig.WakeOnLan = "magic";
    };

    # Secondary WAN interface (USB network card)
    networks."secondary" = {
      matchConfig.Name = secondaryWanInterface;
      networkConfig = {
        Address = "${secondaryWanIP}/24";
        IPv6AcceptRA = false;
        DNS = [
          "1.1.1.1"
          "1.0.0.1"
        ]; # Cloudflare
      };

      # Route in secondary_wan table
      routes = [
        {
          Gateway = secondaryWanGateway;
          Table = "secondary_wan";
        }
      ];

      # Policy routing rule: traffic from secondary WAN IP uses secondary_wan table
      routingPolicyRules = [
        {
          From = "${secondaryWanIP}/32";
          Table = "secondary_wan";
          Priority = 100;
        }
      ];
    };
  };
}
