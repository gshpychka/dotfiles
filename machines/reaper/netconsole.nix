# Streams the kernel log to the netconsole receiver over UDP. The kernel sends it
# straight from the network driver, so messages still go out when the root disk
# has dropped off the bus and nothing can be written to the local journal.
#
# On the receiver:
#   journalctl -t reaper
{
  config,
  pkgs,
  ...
}:
let
  receiverName = config.my.netconsole.host;
  receiverIp = config.my.hosts.${receiverName}.lanIp;
  localIp = config.my.hosts.${config.networking.hostName}.lanIp;
  interface = config.networking.interfaces.eno3.name;
  target = "/sys/kernel/config/netconsole/${receiverName}";
in
{
  boot.kernelModules = [ "netconsole" ];

  systemd.services.netconsole = {
    description = "Kernel log to ${receiverName} over netconsole";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.iproute2
      pkgs.iputils
      pkgs.jq
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "10s";
    };
    script = ''
      # netconsole builds Ethernet frames itself and needs the receiver's MAC,
      # resolved here through ARP
      ping -c 1 -W 2 ${receiverIp} > /dev/null
      mac=$(ip -j neigh show ${receiverIp} dev ${interface} | jq -er '.[0].lladdr')

      mkdir -p ${target}
      echo 0 > ${target}/enabled
      echo ${interface} > ${target}/dev_name
      echo ${localIp} > ${target}/local_ip
      echo ${receiverIp} > ${target}/remote_ip
      echo ${toString config.my.netconsole.port} > ${target}/remote_port
      echo "$mac" > ${target}/remote_mac
      echo 1 > ${target}/enabled

      # netconsole only receives messages below the console log level.
      # boot.consoleLogLevel = 3 keeps boot quiet; once booted, the level goes to 7
      # so warnings such as NVMe timeouts and controller resets reach the receiver.
      # The local console prints them too.
      echo 7 > /proc/sys/kernel/printk
    '';
    preStop = ''
      echo 0 > ${target}/enabled
    '';
  };
}
