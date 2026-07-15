{
  config,
  ...
}:
{
  # Self-hosted push notifications, exposed at ntfy.<domain> through the
  # Cloudflare tunnel (see cloudflare-tunnel.nix). Subscribe from the ntfy
  # mobile app or a browser; any service on the fleet can publish over HTTP
  # with a token. First consumer wired up is Gatus (see gatus.nix).
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.${config.my.domain}";
      # Loopback only: the Cloudflare tunnel is the sole ingress. Set
      # explicitly (matches the module default) so cloudflare-tunnel.nix can
      # reference this exact address rather than duplicate the port.
      listen-http = "127.0.0.1:2586";
      # Trust X-Forwarded-For from cloudflared for rate limiting / real IPs.
      behind-proxy = true;
      # Private instance: nothing is readable or publishable without an
      # account (accounts are provisioned declaratively below).
      auth-default-access = "deny-all";
      # Instant iOS/Android delivery for a self-hosted server: ntfy forwards a
      # content-free poll request to ntfy.sh, whose Firebase/APNs wakes the
      # app, which then fetches the real message back from buoy. Only a topic
      # hash derived from base-url leaves the box; message bodies stay local.
      upstream-base-url = "https://ntfy.sh";
    };
    # Declarative accounts/ACL/tokens via the env file rendered below. ntfy
    # reconciles these against its auth DB on every start and deletes anything
    # no longer listed, so accounts are managed like NixOS users
    # (mutableUsers = false) - never via the `ntfy user` CLI on the box.
    environmentFile = config.sops.templates."ntfy.env".path;
  };

  # ntfy requires a bcrypt password per account even when auth is by token, so
  # both accounts carry a throwaway hash and authenticate with an access token
  # (the "key" analogue - like this box's own key-only login). Only the hashes
  # and tokens are secret; the account/topic/role structure is declared in the
  # template below, the ntfy equivalent of a declarative users.users.* with a
  # hashedPasswordFile.
  #
  # secrets/buoy/ntfy.yaml was generated with a CSPRNG (bcrypt cost 10, 32-char
  # tk_ tokens) and encrypted to the buoy and glib age keys. To read the admin
  # token for the mobile app / browser, or to rotate any value:
  #   sops secrets/buoy/ntfy.yaml
  # It is not yet encrypted to the YubiKey; add it with the usual rekey step:
  #   sops updatekeys secrets/buoy/ntfy.yaml
  sops.secrets = {
    ntfy-admin-password-hash.sopsFile = ../../secrets/buoy/ntfy.yaml;
    ntfy-admin-token.sopsFile = ../../secrets/buoy/ntfy.yaml;
    ntfy-gatus-password-hash.sopsFile = ../../secrets/buoy/ntfy.yaml;
    ntfy-gatus-token.sopsFile = ../../secrets/buoy/ntfy.yaml;
  };

  # admin: role=admin -> read + publish every topic (no ACL entry needed), used
  # from your phone/browser via its token. gatus: write-only to its own topic
  # only. Lists are comma-separated and reconciled on every restart (entries
  # removed here are deleted from the DB). The gatus topic must match gatus.nix.
  sops.templates."ntfy.env" = {
    content = ''
      NTFY_AUTH_USERS=admin:${config.sops.placeholder.ntfy-admin-password-hash}:admin,gatus:${config.sops.placeholder.ntfy-gatus-password-hash}:user
      NTFY_AUTH_ACCESS=gatus:buoy-status:write-only
      NTFY_AUTH_TOKENS=admin:${config.sops.placeholder.ntfy-admin-token},gatus:${config.sops.placeholder.ntfy-gatus-token}
    '';
    restartUnits = [ "ntfy-sh.service" ];
  };
}
