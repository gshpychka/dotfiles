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
      # account. Accounts and per-topic access are provisioned via the ntfy
      # CLI (one-time step below).
      auth-default-access = "deny-all";
      # Instant iOS/Android delivery for a self-hosted server: ntfy forwards a
      # content-free poll request to ntfy.sh, whose Firebase/APNs wakes the
      # app, which then fetches the real message back from buoy. Only a topic
      # hash derived from base-url leaves the box; message bodies stay local.
      upstream-base-url = "https://ntfy.sh";
    };
  };

  # One-time auth setup, run on buoy. State lives in the auth-file at
  # /var/lib/ntfy-sh/user.db and survives reboots and redeploys; it is lost
  # only if the VM is re-created (same durability as Gatus's data.db). The
  # service creates the DB on first start, so run these afterwards. Run as the
  # ntfy-sh service user so the SQLite file keeps the right ownership; the CLI
  # reads the generated config at /etc/ntfy/server.yml automatically.
  #
  #   sudo -u ntfy-sh ntfy user add --role=admin <me>       # app / browser login
  #   sudo -u ntfy-sh ntfy user add gatus                   # status-page publisher
  #   sudo -u ntfy-sh ntfy access gatus buoy-status write-only
  #   sudo -u ntfy-sh ntfy token add --label gatus gatus    # prints tk_...
  #
  # Put the tk_... token in secrets/buoy/gatus.env as NTFY_TOKEN=<token> (sops),
  # then redeploy so Gatus can publish to the buoy-status topic.
}
