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
    services.opkssh.enable = true;

    sops.secrets.opkssh-email = {
      sopsFile = ../../../secrets/common/opkssh.yaml;
      key = "email";
    };

    # upstream builds this file from `authorizations`, which would put the address
    # in the world-readable Nix store; sops-nix owns the path instead
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
