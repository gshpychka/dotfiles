{ config, lib, ... }:

let
  cfg = config.my.cloudflare-ddns;
in
with lib;
{
  options.my.cloudflare-ddns = {
    enable = mkEnableOption "Cloudflare dynamic DNS updater";
  };

  config = mkIf cfg.enable {
    # Set up SOPS secret for API token
    sops.secrets.cloudflare-dns-api-token = {
      sopsFile = ../../../secrets/common/cloudflare.yaml;
    };

    # Configure the built-in Cloudflare Dynamic DNS service
    services.cloudflare-dyndns = {
      enable = true;
      apiTokenFile = config.sops.secrets.cloudflare-dns-api-token.path;
      domains = [ "wan.${config.my.domain}" ];
      proxied = true;
      ipv4 = true;
      ipv6 = false;
      frequency = "*:*:0/30"; # Every 30 seconds
    };
  };
}
