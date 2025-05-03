{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let

  cfg = config.services.sabnzbd;
  inherit (pkgs) sabnzbd;

in

{
  disabledModules = [ "services/networking/sabnzbd.nix" ];

  ###### interface

  options = {
    services.sabnzbd = {
      enable = mkEnableOption "the sabnzbd server";

      package = mkPackageOption pkgs "sabnzbd" { };

      configFile = mkOption {
        type = types.path;
        default = "/var/lib/sabnzbd/sabnzbd.ini";
        description = "Path to config file.";
      };

      user = mkOption {
        default = "sabnzbd";
        type = types.str;
        description = "User to run the service as";
      };

      group = mkOption {
        type = types.str;
        default = "sabnzbd";
        description = "Group to run the service as";
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Open ports in the firewall for the sabnzbd web interface
        '';
      };
    };
  };

  ###### implementation

  config = mkIf cfg.enable {
    users.users = mkIf (cfg.user == "sabnzbd") {
      sabnzbd = {
        uid = config.ids.uids.sabnzbd;
        group = cfg.group;
        description = "sabnzbd user";
      };
    };

    users.groups = mkIf (cfg.group == "sabnzbd") {
      sabnzbd.gid = config.ids.gids.sabnzbd;
    };

    systemd.services.sabnzbd = {
      description = "sabnzbd server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "sabnzbd";
        ExecStart = "${pkgs.sabnzbd}/bin/sabnzbd -f ${cfg.configFile}";
        Restart = "on-failure";
        RequiresMountsFor = [ "/mnt/hoard" ];
        UMask = "002";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      # TODO: decleratively configurable port
      allowedTCPPorts = [ 8085 ];
    };
  };
}
