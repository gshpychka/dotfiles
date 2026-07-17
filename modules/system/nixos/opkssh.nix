{ lib, config, ... }:
# opkssh (OpenPubkey SSH): log in over SSH with a Google identity instead of a
# long-lived key. On the client, `opkssh login` opens a browser, authenticates
# to Google, and writes a short-lived SSH key carrying an OIDC token. sshd's
# AuthorizedKeysCommand runs `opkssh verify`, which checks that token against the
# provider config in /etc/opk and the authorizations below.
#
# This coexists with the usual authorizedKeys.keys entries: sshd still accepts
# the static keys, opkssh just adds the OIDC path on top.
let
  # accounts.google.com is the OIDC issuer for both Gmail and Workspace accounts
  googleIssuer = "https://accounts.google.com";
in
{
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

    # Map the Google account to the main local user. Only emitted once
    # my.googleEmail is set (values.nix); until then opkssh is configured but
    # grants no one access.
    authorizations = lib.optional (config.my.googleEmail != null) {
      user = config.my.user;
      principal = config.my.googleEmail;
      issuer = googleIssuer;
    };
  };
}
