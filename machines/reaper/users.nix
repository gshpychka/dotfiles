{
  pkgs,
  config,
  ...
}:
{
  users = {
    mutableUsers = false;
    defaultUserShell = pkgs.zsh;
    users = {
      ${config.my.user} = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "plugdev"
          "usb"
        ];
        openssh.authorizedKeys.keys = [
          config.my.sshKeys.main
        ];
        linger = true;
        hashedPasswordFile = config.sops.secrets.gshpychka-hashed-password.path;
      };
      hass = {
        group = "homeassistant";
        isSystemUser = true;
        useDefaultShell = true;
        openssh.authorizedKeys.keys = [
          config.my.sshKeys.homeassistant
        ];
      };
    };
    groups.homeassistant = { };
  };
}
