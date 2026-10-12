# The owner's OneDrive, synced both ways on this host by the OneDrive Client
# for Linux (https://github.com/abraunegg/onedrive) under its own user; the
# members of its group read and write the synced tree.
#
# Imperative, one-time: sign in to the owner's Microsoft account (open the
# printed address, paste back the one the browser ends on), then start the sync:
#   sudo -Hu onedrive onedrive --display-quota
#   sudo systemctl start onedrive
#
# Imperative, whenever the service has stopped on a required --resync:
#   sudo -Hu onedrive onedrive --sync --resync
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
  # the client's default, holding the sign-in (refresh_token) and the sync database
  confDir = "${home}/.config/onedrive";
  # the client applies the modes to what it creates, and demands a --resync
  # when sync_dir changes
  clientConfig = pkgs.writeText "onedrive-config" ''
    sync_dir = "${cfg.syncDir}"
    sync_dir_permissions = "770"
    sync_file_permissions = "660"
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
      "d ${home} 0750 ${user} ${cfg.group} - -"
      "d ${home}/.config 0700 ${user} ${cfg.group} - -"
      "d ${confDir} 0700 ${user} ${cfg.group} - -"
      "L+ ${confDir}/config - - - - ${clientConfig}"
      # setgid: the group owns whatever a member creates inside
      "d ${cfg.syncDir} 2770 ${user} ${cfg.group} - -"
      # a default ACL exempts new entries from their creator's umask, so a
      # member's files are group-writable whatever its umask
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
      serviceConfig = {
        User = user;
        Group = cfg.group;
        ExecStart = "${lib.getExe pkgs.onedrive} --monitor";
        Restart = "on-failure";
        RestartSec = "5min";
        # a required --resync
        RestartPreventExitStatus = 126;
        UMask = "0077";
      };
    };
  };
}
