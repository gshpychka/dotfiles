{ config, pkgs, ... }:
let
  secondaryWanInterface = "enp0s20f0u4";
  secondaryWanIP = "109.86.45.81";
  secondaryWanGateway = "109.86.45.254";
  plexNamespaceIP = "10.200.0.2";
  plexHostVethIP = "10.200.0.1";
in
{
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };

  networking = {
    hostName = "hoard";
    usePredictableInterfaceNames = true;
    enableIPv6 = false;
    useNetworkd = true;
    useDHCP = false;
    firewall = {
      logRefusedConnections = false;
      extraCommands = ''
        # Enable NAT for plex namespace traffic going out secondary WAN
        iptables -t nat -A POSTROUTING -s ${plexNamespaceIP}/32 -o ${secondaryWanInterface} -j SNAT --to-source ${secondaryWanIP}

        # Port forward from host to Plex namespace (port 32400)
        iptables -t nat -A PREROUTING -i enp1s0 -p tcp --dport 32400 -j DNAT --to-destination ${plexNamespaceIP}:32400
        iptables -t nat -A PREROUTING -i ${secondaryWanInterface} -p tcp --dport 32400 -j DNAT --to-destination ${plexNamespaceIP}:32400

        # Allow forwarding from plex namespace
        iptables -A FORWARD -s ${plexNamespaceIP}/32 -j ACCEPT
        iptables -A FORWARD -d ${plexNamespaceIP}/32 -j ACCEPT
      '';
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
    networks."10-primary" = {
      matchConfig.Name = "enp1s0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
    };

    links."10-primary" = {
      matchConfig.Name = "enp1s0";
      linkConfig.WakeOnLan = "magic";
    };

    # Secondary WAN interface
    networks."20-secondary-wan" = {
      matchConfig.Name = secondaryWanInterface;
      networkConfig = {
        Address = "${secondaryWanIP}/24";
        IPv6AcceptRA = false;
        DNS = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };

      routes = [
        {
          Gateway = secondaryWanGateway;
          Table = "secondary_wan";
        }
      ];

      routingPolicyRules = [
        {
          From = "${secondaryWanIP}/32";
          Table = "secondary_wan";
          Priority = 100;
        }
      ];
    };

    # TODO: tidy up / move near plex
    # Veth pair for Plex namespace - host side
    netdevs."30-veth-plex" = {
      netdevConfig = {
        Kind = "veth";
        Name = "veth-plex-host";
      };
      peerConfig.Name = "veth-plex-ns";
    };

    networks."30-veth-plex-host" = {
      matchConfig.Name = "veth-plex-host";
      networkConfig.Address = "${plexHostVethIP}/24";

      routingPolicyRules = [
        {
          From = "${plexNamespaceIP}/32";
          Table = "secondary_wan";
          Priority = 50;
        }
      ];
    };
  };

  # Plex namespace setup
  systemd.services.plex-namespace = {
    description = "Network namespace for Plex";
    before = [ "plex.service" ];
    wants = [ "sys-subsystem-net-devices-veth\\x2dplex\\x2dns.device" ];
    after = [
      "network.target"
      "systemd-networkd.service"
    ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Create network namespace
      ip netns add plex

      # Move veth peer into namespace
      ip link set veth-plex-ns netns plex

      # Configure namespace side
      ip netns exec plex ip addr add ${plexNamespaceIP}/24 dev veth-plex-ns
      ip netns exec plex ip link set veth-plex-ns up
      ip netns exec plex ip link set lo up
      ip netns exec plex ip route add default via ${plexHostVethIP}

      # Configure DNS in namespace
      mkdir -p /etc/netns/plex
      cat > /etc/netns/plex/resolv.conf <<EOF
      nameserver 1.1.1.1
      nameserver 1.0.0.1
      EOF
    '';

    preStop = ''
      ip netns delete plex 2>/dev/null || true
    '';
  };

  systemd.services.plex = {
    serviceConfig = {
      NetworkNamespacePath = "/var/run/netns/plex";
      BindReadOnlyPaths = [ "/etc/netns/plex/resolv.conf:/etc/resolv.conf" ];
    };
  };
}
