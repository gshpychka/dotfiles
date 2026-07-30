{ lib, config, ... }:
# opkssh (OpenPubkey SSH): log in over SSH with a Google identity instead of a
# long-lived key.
let
  cfg = config.my.opkssh;
  opk = config.services.opkssh;
  googleIssuer = "https://accounts.google.com";
in
{
  options.my.opkssh = {
    enable = lib.mkEnableOption "opkssh, for SSH login with a Google identity";
  };

  config = lib.mkIf cfg.enable {
    services.opkssh = {
      enable = true;

      providers.google = {
        issuer = googleIssuer;
        # opkssh's public Google desktop client, the same value nixpkgs ships as
        # the services.opkssh.providers default:
        # https://github.com/NixOS/nixpkgs/blob/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5/nixos/modules/services/networking/opkssh/opkssh.nix#L76
        clientId = "206584157355-7cbe4s640tvm7naoludob4ut1emii7sf.apps.googleusercontent.com";
        # short-lived: `opkssh login` must be re-run once the key expires
        lifetime = "24h";
      };
    };

    sops.secrets.opkssh-email = {
      sopsFile = ../../../secrets/common/opkssh.yaml;
      key = "email";
    };

    # we construct the file ourselves via sops-nix
    environment.etc."opk/auth_id".enable = false;
    sops.templates."opk-auth_id" = {
      # line format: "<linux user> <principal> <issuer>"
      content = "${config.my.user} ${config.sops.placeholder.opkssh-email} ${googleIssuer}";
      path = "/etc/opk/auth_id";
      owner = opk.user;
      inherit (opk) group;
      mode = "0640";
    };
  };
}
