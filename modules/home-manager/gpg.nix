{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  cfg = config.my.gpg;
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  options.my.gpg = {
    enable = lib.mkEnableOption "GPG configuration";
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals (osConfig != null && !isDarwin) [
      {
        assertion = osConfig.services.pcscd.enable or false;
        message = "my.gpg requires services.pcscd.enable = true in NixOS config";
      }
      {
        assertion = osConfig.hardware.gpgSmartcards.enable or false;
        message = "my.gpg requires hardware.gpgSmartcards.enable = true in NixOS config";
      }
      {
        assertion = osConfig.programs.gnupg.agent.enable or false;
        message = "my.gpg requires programs.gnupg.agent.enable = true in NixOS config";
      }
    ];

    home.packages = lib.mkIf isDarwin [
      pkgs.pinentry_mac
    ];

    # user-level config files only
    # system-level agent and hardware access is handled by NixOS
    programs.gpg = {
      enable = true;
      # use pcscd instead of internal CCID driver to avoid conflicts
      scdaemonSettings = {
        disable-ccid = true;
      };
      publicKeys = [
        {
          source = ../../yubikey.pub;
          trust = 5; # ultimate
        }
      ];
    };

    # on Darwin, configure gpg-agent manually since services.gpg-agent doesn't work
    # pinentry-mac provides a GUI prompt for YubiKey PIN
    home.file.".gnupg/gpg-agent.conf" = lib.mkIf isDarwin {
      text = ''
        pinentry-program ${pkgs.pinentry_mac}/bin/pinentry-mac
      '';
    };
  };
}
