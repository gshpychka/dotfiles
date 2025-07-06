{ config, lib, ... }:

let
  cfg = config.my.duckdns;
in
with lib;
{
  options.my.duckdns = {
    enable = mkEnableOption "DuckDNS dynamic DNS updater";
  };

  config = mkIf cfg.enable {
    # Set up SOPS secrets
    sops.secrets.duckdns-domain = {
      sopsFile = ../../../secrets/common/duckdns.yaml;
      key = "domain";
    };

    sops.secrets.duckdns-token = {
      sopsFile = ../../../secrets/common/duckdns.yaml;
      key = "token";
    };

    # Create separate files for domain and token using SOPS templates
    sops.templates."duckdns-domain" = {
      content = config.sops.placeholder.duckdns-domain;
    };

    sops.templates."duckdns-token" = {
      content = config.sops.placeholder.duckdns-token;
    };

    # Configure the built-in DuckDNS service
    services.duckdns = {
      enable = true;
      domainsFile = config.sops.templates."duckdns-domain".path;
      tokenFile = config.sops.templates."duckdns-token".path;
    };

    # Ensure DuckDNS waits for network to be fully online
    systemd.services.duckdns = {
      after = [ "network-online.target" "nss-lookup.target" ];
      wants = [ "network-online.target" "nss-lookup.target" ];
    };
  };
}