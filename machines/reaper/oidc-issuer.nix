# OIDC issuers for AWS federation (github:gshpychka/oidc-issuer), publishing
# through reaper-tunnel (cloudflare-tunnel.nix).
{ config, inputs, ... }:
{
  imports = [ inputs.oidc-issuer.nixosModules.default ];

  services.oidc-issuer.simple = {
    enable = true;
    host = "tokens.${config.my.domain}";
    clients = [ config.my.user ];
  };

  services.oidc-issuer.spire = {
    # off until bootstrapped: needs tpmEkHash (the oidc-issuer README's SPIRE steps)
    enable = false;
    host = "spire.${config.my.domain}";
    trustDomain = config.my.domain;
    users = [ config.my.user ];
  };
}
