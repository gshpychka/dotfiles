# The owner's OneDrive, synced both ways into the agent's workspace by the
# OneDrive Client for Linux (https://github.com/abraunegg/onedrive), where the
# agent's file tools and sandboxed sessions reach it.
#
# Imperative, one-time: sign in to the owner's Microsoft account (open the
# printed address, paste back the one the browser ends on), then start the sync:
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
  # one set of settings for every invocation: the client demands a --resync
  # when its sync directory changes
  onedrive = "${lib.getExe pkgs.onedrive} --confdir ${confDir} --syncdir ${syncDir}";

  # The client, run as the gateway user.
  cli = pkgs.writeShellApplication {
    inherit name;
    text = ''
      if [ "$(id -un)" != ${gw.user} ]; then
        exec sudo -u ${gw.user} -- "$0" "$@"
      fi
      # the caller's directory may be closed to the gateway user
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
      # tmpfiles creates a missing parent as root
      "d ${cfg.workspace} 0700 ${gw.user} ${gw.group} - -"
      "d ${confDir} 0700 ${gw.user} ${gw.group} - -"
      "d ${syncDir} 0700 ${gw.user} ${gw.group} - -"
    ];

    systemd.services.${name} = {
      description = "OneDrive sync into the OpenClaw workspace";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # requires the owner's sign-in
      unitConfig.ConditionPathExists = "${confDir}/refresh_token";
      serviceConfig = {
        User = gw.user;
        Group = gw.group;
        ExecStart = "${onedrive} --monitor";
        Restart = "on-failure";
        RestartSec = "5min";
        # the client's exit statuses for a required --resync (126 through 2.5.11,
        # 78 on upstream's master); recover with `openclaw-onedrive --sync --resync`
        # and a restart
        RestartPreventExitStatus = [
          78
          126
        ];
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
