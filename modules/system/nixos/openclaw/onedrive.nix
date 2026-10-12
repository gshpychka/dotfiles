# The owner's OneDrive, synced both ways into the agent's workspace by the
# OneDrive Client for Linux (https://github.com/abraunegg/onedrive).
#
# Imperative, one-time: sign in to the owner's Microsoft account (open the
# printed address, paste back the one the browser ends on), then start the sync:
#   sudo -iu openclaw onedrive --display-quota
#   sudo systemctl start openclaw-onedrive
#
# Imperative, whenever the service has stopped on a required --resync:
#   sudo -iu openclaw onedrive --sync --resync
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
  home = config.users.users.${gw.user}.home;
  # the client's default for the gateway user, holding the sign-in
  # (refresh_token) and the sync database
  confDir = "${home}/.config/onedrive";
  syncDir = "${cfg.workspace}/onedrive";
  # every run as the gateway user reads it: the client demands a --resync when
  # its sync directory changes
  clientConfig = pkgs.writeText "onedrive-config" ''
    sync_dir = "${syncDir}"
  '';
in
{
  options.my.openclaw.onedrive.enable =
    lib.mkEnableOption "the owner's OneDrive in the agent's workspace, synced both ways";

  config = lib.mkIf (cfg.enable && cfg.onedrive.enable) {
    systemd.tmpfiles.rules = [
      "d ${home}/.config 0700 ${gw.user} ${gw.group} - -"
      "d ${confDir} 0700 ${gw.user} ${gw.group} - -"
      "L+ ${confDir}/config - - - - ${clientConfig}"
      "d ${syncDir} 0700 ${gw.user} ${gw.group} - -"
    ];

    users.users.${gw.user}.packages = [ pkgs.onedrive ];

    systemd.services.openclaw-onedrive = {
      description = "OneDrive sync into the OpenClaw workspace";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # requires the owner's sign-in
      unitConfig.ConditionPathExists = "${confDir}/refresh_token";
      serviceConfig = {
        User = gw.user;
        Group = gw.group;
        ExecStart = "${lib.getExe pkgs.onedrive} --monitor";
        Restart = "on-failure";
        RestartSec = "5min";
        # a required --resync
        RestartPreventExitStatus = 126;
        UMask = "0077";
      };
    };

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
