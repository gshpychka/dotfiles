# https://github.com/DylanRJohnston/nixos/blob/362a8253d8b80d09b23b91a9c1e58695b735bd5b/common/nix-darwin/touchID.nix#L19
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.security.pam;
in {
  options = {
    security.pam.enableSudoTouchId = mkEnableOption ''
      Enable sudo authentication with Touch ID

      pam_watchid has to be installed manually beforehand
      https://github.com/biscuitehh/pam-watchid

    '';
  };

  config = lib.mkIf (cfg.enableSudoTouchId) {
    environment.etc."pam.d/sudo_local" = {
      text = ''
        auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
        auth       sufficient     pam_tid.so
        auth       sufficient     pam_watchid.so
      '';
    };
  };
}
