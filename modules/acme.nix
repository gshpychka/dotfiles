{ config, lib, ... }:

let
  cfg = config.my.acme;
  domain = "glib.sh";
in
with lib;
{

  options.my.acme = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Turn on Cloudflare-based ACME integration.";
    };

    extraDomainNames = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional SANs to include on the same certificate.";
      example = [ "alt.${domain}" ];
    };
  };

  config = mkIf cfg.enable {

    networking.domain = domain;

    sops.secrets.cloudflare-api-token = {
      sopsFile = ../secrets/common/cloudflare.yaml;
      key = "cloudflare-dns-api-token";
    };

    sops.templates."acme.env" = {
      content = ''
        CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare-api-token}
      '';
      mode = "0400";
    };

    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "acme@${domain}";
        dnsProvider = "cloudflare";
        environmentFile = config.sops.templates."acme.env".path;
        reloadServices = [ "nginx" ];
        group = "acme";
      };

      certs."${config.networking.fqdn}" = {
        extraDomainNames = cfg.extraDomainNames;
      };
    };

    # Let nginx read the key
    users.groups.acme.members = [ "nginx" ];
  };
}
