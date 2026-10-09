# Receives syslog over UDP from LAN devices that keep their own logs in RAM, and
# stores it in harbor's journal so the logs survive the device crashing or
# rebooting. Retention and rotation follow harbor's journald limits.
#
# Each sender's messages carry its name as the syslog identifier:
#   journalctl -t router
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

      # the journal's MESSAGE field carries "<program>: <text>"; the sender's
      # program name is also kept in its own field for filtering
      template(name="remoteJournal" type="list") {
        property(name="$!sender" outname="SYSLOG_IDENTIFIER")
        property(name="syslogseverity" outname="PRIORITY")
        property(name="programname" outname="REMOTE_PROGRAM")
        property(name="$!message" outname="MESSAGE")
      }

      # UDP syslog is unauthenticated; only datagrams from a listed sender
      # address are kept, everything else is dropped
      ruleset(name="remote" queue.type="LinkedList") {
        ${lib.concatStrings (
          lib.mapAttrsToList (name: address: ''
            if $fromhost-ip == "${address}" then {
              set $!sender = "${name}";
              set $!message = $programname & ":" & $msg;
              action(type="omjournal" template="remoteJournal")
            }
          '') senders
        )}
        stop
      }
    '';
  };

  # The rsyslogd module turns on journal → syslog forwarding by default; rsyslog
  # here only receives from the network
  services.journald.settings.Journal.ForwardToSyslog = false;

  networking.firewall.interfaces.${lanInterface}.allowedUDPPorts = [ syslogPort ];
}
