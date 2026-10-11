# The owner's OneDrive, synced both ways into the agent's workspace by the
# OneDrive Client for Linux (https://github.com/abraunegg/onedrive), so the
# agent's file tools and sandboxed sessions reach it like any other workspace
# file. Local changes upload within seconds; online changes arrive by the next
# monitor_interval (5 minutes by default).
#
# Imperative, one-time: sign in to the owner's Microsoft account. The command
# prints an address to open in a browser and asks for the address the browser
# ends on; then start the sync, whose first run downloads the whole drive:
#   openclaw-onedrive --display-quota
#   sudo systemctl start openclaw-onedrive
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  name = "openclaw-onedrive";
  # client state: the sign-in (refresh_token) and the sync database
  confDir = "${gw.stateDir}/onedrive";
  syncDir = "${cfg.workspace}/onedrive";
  # The client keeps a hash of its settings and wants a --resync when the
  # sync directory changes, so every invocation passes the same ones.
  onedrive = "${lib.getExe pkgs.onedrive} --confdir ${confDir} --syncdir ${syncDir}";

  # The client as the gateway user, for the owner's sign-in and checks.
  cli = pkgs.writeShellApplication {
    inherit name;
    text = ''
      if [ "$(id -un)" != ${gw.user} ]; then
        exec sudo -u ${gw.user} -- "$0" "$@"
      fi
      # the caller's directory, such as a home, may be closed to the gateway user
      [ -x . ] || cd ${gw.stateDir}
      exec ${onedrive} "$@"
    '';
  };
in
{
  options.my.openclaw.onedrive.enable =
    lib.mkEnableOption "the owner's OneDrive in the agent's workspace, synced both ways";

  config = lib.mkIf (cfg.enable && cfg.onedrive.enable) {
    systemd.tmpfiles.rules = [
      # as the gateway creates it, so the rules below can't leave it to root
      "d ${cfg.workspace} 0700 ${gw.user} ${gw.group} - -"
      "d ${confDir} 0700 ${gw.user} ${gw.group} - -"
      "d ${syncDir} 0700 ${gw.user} ${gw.group} - -"
    ];

    systemd.services.${name} = {
      description = "OneDrive sync into the OpenClaw workspace";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # until the owner signs in
      unitConfig.ConditionPathExists = "${confDir}/refresh_token";
      serviceConfig = {
        User = gw.user;
        Group = gw.group;
        ExecStart = "${onedrive} --monitor";
        Restart = "on-failure";
        RestartSec = "5min";
        UMask = "0077";
      };
    };

    environment.systemPackages = [ cli ];

    my.openclaw.skills.onedrive = {
      description = "The owner's OneDrive, synced both ways as onedrive/ in your workspace.";
      text = ''
        `onedrive/` in your workspace is the owner's whole OneDrive, kept in
        sync both ways: what you create, change, move or delete there changes
        on OneDrive within seconds, and changes made elsewhere arrive within
        about 5 minutes. Use the normal file tools.

        A deletion here deletes on OneDrive too, where its recycle bin keeps
        it for 30 days; removing more than 1000 items at once stops the sync
        until the owner confirms. Never delete, move or replace the
        `onedrive` directory itself.
      '';
    };
  };
}
