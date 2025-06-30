{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.my.sudoTouchId;
in
{
  options = {
    my.sudoTouchId.enable = mkEnableOption ''
      Enable sudo authentication with Touch ID
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "Touch ID is only supported on macOS";
      }
    ];
    security.pam.services.sudo_local = {
      touchIdAuth = true;
      watchIdAuth = true;
      reattach = true;
    };
  };
}
