{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.security.pam;
in
{
  options = {
    security.pam.enableSudoTouchId = mkEnableOption ''
      Enable sudo authentication with Touch ID

      pam_watchid has to be installed manually beforehand
      https://github.com/biscuitehh/pam-watchid
    '';
  };

  config = lib.mkIf (cfg.enableSudoTouchId) {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "sudo with Touch ID is only supported on macOS";
      }
    ];
    environment.etc."pam.d/sudo_local" = {
      text = ''
        auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
        auth       sufficient     pam_tid.so
        auth       sufficient     pam_watchid.so
      '';
    };
  };
}
