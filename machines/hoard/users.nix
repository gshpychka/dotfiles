{
  pkgs,
  config,
  ...
}:
{
  users = {
    groups.media = {
      members = [
        config.users.users.${config.my.user}.name
      ];
    };
    users = {
      ${config.my.user} = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "plugdev"
          "usb"
        ];
        packages = with pkgs; [
          git
          sysstat
          iotop
          fio
          smartmontools
        ];
        openssh.authorizedKeys.keys = [
          config.my.sshKeys.main
        ];
        # TODO: sops-nix
        initialHashedPassword = "";
      };
      "time-machine" = {
        group = config.users.groups.media.name;
        isSystemUser = true;
      };
      "kodi" = {
        group = config.users.groups.media.name;
        isSystemUser = true;
      };
    };
  };
}