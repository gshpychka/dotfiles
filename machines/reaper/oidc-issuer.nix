# OIDC issuers for AWS federation (github:gshpychka/oidc-issuer). reaper runs
# both halves of each, publishing through reaper-tunnel (cloudflare-tunnel.nix).
{ config, inputs, ... }:
{
  imports = [ inputs.oidc-issuer.nixosModules.default ];

  services.oidc-issuer.simple = {
    host = "tokens.${config.my.domain}";
    # printed by `sudo oidc-issuer-keygen`
    publicKeys = [
      {
        kid = "0PHAEBXyufo1YMYRB-k9WKjmXtTAYHbBgBo419SzW2k";
        x = "-4RRmQGoX9GxrfuAf5op_dH1VOwerEzV9gG0wNumCik";
        y = "nxQwKSRmPlAymGmE32Ly_CB-z6J3hgFGdi2k6tzcmVk";
      }
    ];
    signer = {
      enable = true;
      activeKid = "0PHAEBXyufo1YMYRB-k9WKjmXtTAYHbBgBo419SzW2k";
      clients = [ config.my.user ];
    };
    publisher.enable = true;
  };

  services.oidc-issuer.spire = {
    # off until bootstrapped: needs tpmEkHash (the oidc-issuer README's SPIRE steps)
    enable = false;
    host = "spire.${config.my.domain}";
    trustDomain = config.my.domain;
    users = [ config.my.user ];
  };
}
