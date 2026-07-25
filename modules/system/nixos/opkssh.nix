{ lib, config, ... }:
# opkssh (OpenPubkey SSH): log in over SSH with a Google identity instead of a
# long-lived key. On the client, `opkssh login` opens a browser, authenticates
# to Google, and writes a short-lived SSH key carrying an OIDC token. sshd's
# AuthorizedKeysCommand runs `opkssh verify`, which checks that token against the
# provider config in /etc/opk and the authorization below.
#
# This coexists with the usual authorizedKeys.keys entries: sshd still accepts
# the static keys, opkssh just adds the OIDC path on top.
#
# Opt-in per machine rather than fleet-wide, following the other secret-consuming
# modules: the authorized address is decrypted from sops, and the installer ISO
# has no age key in .sops.yaml to decrypt it with.
let
  cfg = config.my.opkssh;
  opk = config.services.opkssh;
  # accounts.google.com is the OIDC issuer for both Gmail and Workspace accounts
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
        # public OAuth client shipped with opkssh for Google login; this is a
        # well-known desktop client id, not a secret
        clientId = "206584157355-7cbe4s640tvm7naoludob4ut1emii7sf.apps.googleusercontent.com";
        # short-lived: `opkssh login` must be re-run once the key expires
        lifetime = "24h";
      };

      # deliberately empty: upstream renders `authorizations` into /etc/opk/auth_id
      # via environment.etc, which would publish the account address in the
      # world-readable Nix store. Rendered from sops below instead.
      authorizations = [ ];
    };

    sops.secrets.opkssh-email = {
      sopsFile = ../../../secrets/common/opkssh.yaml;
      key = "email";
    };

    # auth_id lines are "<linux user> <principal> <issuer>". Drop upstream's
    # store-backed copy and let sops-nix own the path; it creates the parent
    # directory and links the rendered file in at activation.
    environment.etc."opk/auth_id".enable = false;
    sops.templates."opk-auth_id" = {
      content = "${config.my.user} ${config.sops.placeholder.opkssh-email} ${googleIssuer}";
      path = "/etc/opk/auth_id";
      owner = opk.user;
      group = opk.group;
      mode = "0640";
    };
  };
}
