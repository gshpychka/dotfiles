{
  config,
  ...
}:
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.${config.my.domain}";
      listen-http = "127.0.0.1:2586";
      # cloudflared is the only ingress, so X-Forwarded-For carries the client address
      behind-proxy = true;
      auth-default-access = "deny-all";
      # ntfy.sh relays a content-free poll request to wake the iOS/Android apps
      upstream-base-url = "https://ntfy.sh";
    };
    # ntfy reconciles its auth DB against these lists on start and deletes unlisted entries
    environmentFile = config.sops.templates."ntfy.env".path;
  };

  # ntfy requires a bcrypt password per account; admin and gatus authenticate with the tk_ tokens
  sops.secrets = {
    ntfy-admin-password-hash.sopsFile = ../../secrets/buoy/ntfy.yaml;
    ntfy-admin-token.sopsFile = ../../secrets/buoy/ntfy.yaml;
    ntfy-gatus-password-hash.sopsFile = ../../secrets/buoy/ntfy.yaml;
    ntfy-gatus-token.sopsFile = ../../secrets/buoy/ntfy.yaml;
    ntfy-reader-password-hash.sopsFile = ../../secrets/buoy/ntfy.yaml;
  };

  sops.templates."ntfy.env" = {
    content = ''
      NTFY_AUTH_USERS=admin:${config.sops.placeholder.ntfy-admin-password-hash}:admin,gatus:${config.sops.placeholder.ntfy-gatus-password-hash}:user,reader:${config.sops.placeholder.ntfy-reader-password-hash}:user
      NTFY_AUTH_ACCESS=gatus:${config.services.gatus.settings.alerting.ntfy.topic}:write-only,reader:${config.services.gatus.settings.alerting.ntfy.topic}:read-only
      NTFY_AUTH_TOKENS=admin:${config.sops.placeholder.ntfy-admin-token},gatus:${config.sops.placeholder.ntfy-gatus-token}
    '';
    restartUnits = [ "ntfy-sh.service" ];
  };
}
