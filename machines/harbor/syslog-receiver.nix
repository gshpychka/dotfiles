# Receives syslog over UDP from LAN devices that keep their own logs in RAM, and
# stores it in harbor's journal so the logs survive the device crashing or
# rebooting. Retention and rotation follow harbor's journald limits.
#
# Each sender's messages carry its name as the syslog identifier, and the
# sending program in REMOTE_PROGRAM:
#   journalctl -t router
#   journalctl -t router REMOTE_PROGRAM=dnsmasq
{
  config,
  lib,
  ...
}:
let
  lanInterface = "eth0";
  syslogPort = 514;

  # name (journal identifier) → source address
  senders = {
    # ASUS web UI (imperative):
    #   System Log → General Log → Remote Log Server = 192.168.1.2, port 514
    # Mesh nodes take the remote log setting from the router
    router = config.my.lan.routerIp;
    zenwifi-cc10 = config.my.hosts.zenwifi-cc10.lanIp;
    zenwifi-e288 = config.my.hosts.zenwifi-e288.lanIp;
  };

  # name (journal identifier) → source address, for hosts streaming their kernel
  # log with netconsole (e.g. machines/reaper/netconsole.nix)
  netconsoleSenders = {
    reaper = config.my.hosts.reaper.lanIp;
  };

  # one omjournal action per sender, matched on its source address
  senderRules =
    templatePrefix: senderSet:
    lib.concatStrings (
      lib.mapAttrsToList (name: address: ''
        if $fromhost-ip == "${address}" then {
          action(type="omjournal" template="${templatePrefix}-${name}")
        }
      '') senderSet
    );
in
{
  services.rsyslogd = {
    enable = true;
    # harbor's own logs stay in journald only; rsyslog handles network input alone
    defaultConfig = "";
    extraConfig = ''
      module(load="imudp")
      module(load="omjournal")

      input(type="imudp" port="${toString syslogPort}" ruleset="remote")
      input(type="imudp" port="${toString config.my.netconsole.port}" ruleset="netconsole")

      # Template fields that read a variable ($!x, $.x) get their outname
      # lowercased, and journald rejects lowercase field names, so each sender
      # has its own template carrying its name as a constant
      ${lib.concatStrings (
        lib.mapAttrsToList (name: _: ''
          template(name="remote-${name}" type="list") {
            constant(value="${name}" outname="SYSLOG_IDENTIFIER")
            property(name="syslogseverity" outname="PRIORITY")
            property(name="programname" outname="REMOTE_PROGRAM")
            property(name="msg" outname="MESSAGE")
          }
        '') senders
      )}

      # netconsole sends bare kernel log lines with no syslog header, so the
      # datagram is the message
      ${lib.concatStrings (
        lib.mapAttrsToList (name: _: ''
          template(name="netconsole-${name}" type="list") {
            constant(value="${name}" outname="SYSLOG_IDENTIFIER")
            constant(value="kernel" outname="REMOTE_PROGRAM")
            property(name="rawmsg" outname="MESSAGE" droplastlf="on")
          }
        '') netconsoleSenders
      )}

      # UDP is unauthenticated; only datagrams from a listed sender address are
      # kept, everything else is dropped
      ruleset(name="remote" queue.type="LinkedList") {
        ${senderRules "remote" senders}
        stop
      }

      ruleset(name="netconsole" queue.type="LinkedList") {
        ${senderRules "netconsole" netconsoleSenders}
        stop
      }
    '';
  };

  # The rsyslogd module turns on journal → syslog forwarding by default; rsyslog
  # here only receives from the network
  services.journald.settings.Journal.ForwardToSyslog = false;

  networking.firewall.interfaces.${lanInterface}.allowedUDPPorts = [
    syslogPort
    config.my.netconsole.port
  ];
}
