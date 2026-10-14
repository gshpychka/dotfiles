# Twingate client for work resources: a user device signed in by hand through SSO, reachable only through a local
# HTTP proxy. Reaper runs agents, so a session exists only between `twingate start` and the daemon stopping.
#
# One-time, after the first switch (setup's autostart and saved-auth answers are overridden below):
#   sudo twingate setup       # asks for the Twingate network name
# Each use:
#   twingate start            # starts the daemon; the sign-in URL to open on eve is also in `twingate status`
#   twingate stop --purge     # stops the daemon and clears its tokens
# Clients reach resources through the proxy, e.g. `https_proxy=http://127.0.0.1:<proxyPort> curl ...`. Clients without
# HTTP proxy support go through a local bridge, e.g. for Postgres:
#   socat TCP-LISTEN:15432,bind=127.0.0.1,fork PROXY:127.0.0.1:<db-host>:5432,proxyport=<proxyPort>
{ lib, pkgs, ... }:
let
  proxyPort = 8118;

  # the file `twingate config networking` writes
  networkConfig = pkgs.writeText "twingate-network-config.json" (
    builtins.toJSON {
      tun = "off";
      http_proxy = "127.0.0.1:${toString proxyPort}";
    }
  );

  # the files behind the CLI's autostart, save-auth-data and networking settings, which the daemon reads at start
  pinSettings = pkgs.writeShellScript "twingate-pin-settings" ''
    printf '0\n' > /etc/twingate/autostart.conf
    printf '0\n' > /etc/twingate/save_auth_data.conf
    ${pkgs.coreutils}/bin/install -m 0644 ${networkConfig} /etc/twingate/network-config.json
  '';
in
{
  services.twingate.enable = true;

  # `twingate setup` writes into /etc/twingate, which the daemon's first start creates; the daemon also writes its
  # device identity there, so the directory stays writable
  systemd.tmpfiles.rules = [ "d /etc/twingate 0755 root root -" ];

  # the module enables resolved for TUN mode's DNS; HTTP-proxy mode resolves resource names inside the daemon
  services.resolved.enable = lib.mkForce false;

  systemd.services.twingate = {
    # `twingate start` runs `systemctl start twingate`
    wantedBy = lib.mkForce [ ];
    serviceConfig = {
      # tokens live only in the daemon's memory, so every start needs a fresh sign-in; `+` runs it with full
      # privileges, as the package's defaults are copied read-only and the unit's capabilities exclude CAP_DAC_OVERRIDE
      ExecStartPre = [ "+${pinSettings}" ];
      # a forgotten session ends after a working day; the package unit's Restart=always would bring the daemon back
      RuntimeMaxSec = "8h";
      Restart = "no";
    };
  };
}
