{ lib, ... }:
let
  secondaryWanInterface = "enp0s20f0u4"; # USB network card
  secondaryWanIP = "172.22.219.83";
  secondaryWanGateway = "172.22.219.254";
in
{
  networking = {
    hostName = "hoard";
    usePredictableInterfaceNames = true;
    enableIPv6 = false;
    interfaces = {
      enp1s0 = {
        useDHCP = true;
        wakeOnLan.enable = true;
      };
      ${secondaryWanInterface} = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = secondaryWanIP;
            prefixLength = 24;
          }
        ];
      };
    };
    nameservers = [
      # cloudflare
      "1.1.1.1"
      "1.0.0.1"
    ];
    useDHCP = lib.mkDefault true;
    iproute2 = {
      enable = true;
      rttablesExtraConfig = ''
        100 secondary_wan
      '';
    };
    localCommands = ''
      ip route add default via ${secondaryWanGateway} dev ${secondaryWanInterface} table secondary_wan
      ip rule add from ${secondaryWanIP} table secondary_wan
    '';
    firewall = {
      logRefusedConnections = false;
    };
  };
}
