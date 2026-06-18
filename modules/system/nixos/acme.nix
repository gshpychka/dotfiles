{ config, lib, ... }:

let
  cfg = config.my.acme;
in
with lib;
{

  options.my.acme = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Turn on Cloudflare-based ACME integration.";
    };

    domain = mkOption {
      type = types.str;
      default = config.my.domain;
      description = "Base domain used for ACME registration.";
    };

    extraDomainNames = mkOption {
      type = types.listOf types.str;
      # wildcard for this machine's subdomains, e.g. *.hoard.glib.sh
      default = [ "*.${config.networking.fqdn}" ];
      description = "Additional SANs to include on the same certificate.";
      example = [ "alt.example.com" ];
    };
  };

  config = mkIf cfg.enable {

    networking.domain = cfg.domain;

    sops.secrets.cloudflare-api-token = {
      sopsFile = ../../../secrets/common/cloudflare.yaml;
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
        email = "acme@${cfg.domain}";
        dnsProvider = "cloudflare";
        environmentFile = config.sops.templates."acme.env".path;
        reloadServices = lib.mkIf config.services.nginx.enable [ "nginx" ];
        group = "acme";
      };

      certs."${config.networking.fqdn}" = {
        inherit (cfg) extraDomainNames;
      };
    };

    # Let nginx read the key
    users.groups.${config.security.acme.defaults.group}.members =
      lib.mkIf config.services.nginx.enable
        [ "nginx" ];
  };
}
