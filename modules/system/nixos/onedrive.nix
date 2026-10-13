# The owner's OneDrive, synced both ways on this host by the OneDrive Client
# for Linux (https://github.com/abraunegg/onedrive) under its own user.
#
# Imperative, one-time: sign in to the owner's Microsoft account (open the
# printed address, paste back the one the browser ends on), then start the sync:
#   sudo -Hu onedrive onedrive --display-quota
#   sudo systemctl start onedrive
#
# Imperative, whenever the service has stopped on a required --resync:
#   sudo -Hu onedrive onedrive --sync --resync
#   sudo systemctl start onedrive
#
# Imperative, whenever the service fails on a big delete, to confirm it:
#   sudo systemctl stop onedrive
#   sudo -Hu onedrive onedrive --sync --force
#   sudo systemctl start onedrive
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.onedrive;
  user = "onedrive";
  home = "/var/lib/${user}";
  # the client's default for this user
  confDir = "${home}/.config/onedrive";
  clientConfig = pkgs.writeText "onedrive-config" ''
    # a change here makes the client demand a --resync
    sync_dir = "${cfg.syncDir}"
    # entries take their group and modes from the tree's setgid bit and default ACL
    disable_permission_set = "true"
    monitor_interval = "${toString cfg.pollInterval}"
    classify_as_big_delete = "${toString cfg.bigDeleteThreshold}"
  '';
in
{
  options.my.onedrive = {
    enable = lib.mkEnableOption "the owner's OneDrive, synced both ways on this host";

    group = lib.mkOption {
      type = lib.types.str;
      default = user;
      readOnly = true;
      description = "Group whose members read and write the synced tree.";
    };

    syncDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/OneDrive";
      readOnly = true;
      description = "The synced tree.";
    };

    pollInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      readOnly = true;
      description = "Seconds within which a change made elsewhere reaches the synced tree.";
    };

    bigDeleteThreshold = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1000;
      readOnly = true;
      description = "Item count, the folder itself included, from which deleting a folder in the synced tree waits for the owner's confirmation.";
    };
  };

  config = lib.mkIf cfg.enable {
    users = {
      groups.${cfg.group} = { };
      users.${user} = {
        isSystemUser = true;
        inherit (cfg) group;
        inherit home;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${home} 0710 ${user} ${cfg.group} - -"
      "d ${home}/.config 0700 ${user} ${cfg.group} - -"
      "d ${confDir} 0700 ${user} ${cfg.group} - -"
      "L+ ${confDir}/config - - - - ${clientConfig}"
      # setgid: the group owns whatever a member creates inside
      "d ${cfg.syncDir} 2770 ${user} ${cfg.group} - -"
      # a default ACL exempts new entries from their creator's umask
      "a+ ${cfg.syncDir} - - - - d:u::rwx,d:g::rwx,d:o::---"
    ];

    environment.systemPackages = [ pkgs.onedrive ];

    systemd.services.onedrive = {
      description = "OneDrive sync";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # requires the owner's sign-in
      unitConfig.ConditionPathExists = "${confDir}/refresh_token";
      # the config file sits in confDir, outside the unit definition systemd compares
      restartTriggers = [ clientConfig ];
      serviceConfig = {
        User = user;
        ExecStart = "${lib.getExe pkgs.onedrive} --monitor";
        Restart = "on-failure";
        # the failures the client exits on last until the owner acts
        RestartSec = "5min";
        # a required --resync
        RestartPreventExitStatus = 126;
        UMask = "0077";
      };
    };
  };
}
