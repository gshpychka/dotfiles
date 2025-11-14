{ config, lib, ... }:

let
  cfg = config.my.cloudflare-ddns;
in
with lib;
{
  options.my.cloudflare-ddns = {
    enable = mkEnableOption "Cloudflare dynamic DNS updater";
    subdomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "wan" ];
      description = "Subdomains to update with Cloudflare.";
    };
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
      domains = map (subdomain: "${subdomain}.${config.my.domain}") cfg.subdomains;
      frequency = "*:*:0/30"; # Every 30 seconds
    };
  };
}
