{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.my.gaming.enable {
    users.users.jovian = {
      isNormalUser = true;
      extraGroups =
        [
          "plugdev"
          "usb"
        ]
        ++ lib.optional config.hardware.openrazer.enable "openrazer";
      hashedPasswordFile = config.sops.secrets.jovian-hashed-password.path;
    };
  };
}
