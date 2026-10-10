# Only root may open TCP connections to the GCE metadata server.
#
# The metadata server hands an access token for the VM's service account to any
# local process that asks (its only check is a Metadata-Flavor header). While
# grant_vm_sops_age_key_access is on (infra/buoy/sops.tf), that token can read
# the sops age key from Secret Manager, so anything running as gatus, ntfy-sh or
# cloudflared could otherwise decrypt secrets/buoy/* and secrets/common/*. The
# grant is normally off, but a fresh bootstrap leaves it on until it's revoked
# after the first deploy, and the service account may gain other roles later.
#
# Root keeps access because:
# - root can already read the age key from the data disk (sops.age.keyFile),
#   so a token gives it nothing new
# - everything that needs the metadata API runs as root: google-guest-agent and
#   google-{startup,shutdown}-scripts (their units set no User=). OS Login would
#   need more, since its NSS module queries the metadata server from whichever
#   process looks up a user, but it is forced off in ./default.nix.
#
# meta skuid is the socket owner's uid in the initial user namespace, so being
# "root" inside an unprivileged user namespace doesn't get past it.
#
# 169.254.169.254 is also the VPC's DNS resolver (UDP/TCP 53), NTP server
# (UDP 123, networking.timeServers in nixpkgs' GCE config) and DHCP server
# (UDP 67), used by non-root processes: nscd and the Go services' own
# resolvers, systemd-timesyncd and dhcpcd. The metadata API is served over TCP,
# so the rule rejects every TCP port but DNS's and leaves UDP alone.
#
# Assumes IPv4 only: the subnet in infra/buoy/network.tf has no IPv6 stack. If
# it gains one, the metadata server gets an IPv6 address that needs the same
# rule.
#
# networking.firewall stays off (nixpkgs' GCE config: inbound is left to the GCP
# firewall in infra/buoy/network.tf). This table only hooks output, so inbound
# traffic is unaffected. networking.nftables also blacklists the legacy
# ip_tables module, which is fine: nixpkgs' iptables is the nft-backed one.
#
# Fails open: if nftables.service doesn't load the table, nothing blocks the
# metadata server. The ruleset is checked at build time
# (networking.nftables.checkRuleset).
#
# Check on buoy, printing only the HTTP status so no token lands in scrollback
# (expect a refused connection for nobody and 200 for root):
#   url=http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
#   sudo -u nobody curl -sS -o /dev/null -w '%{http_code}\n' -H 'Metadata-Flavor: Google' $url
#   sudo curl -sS -o /dev/null -w '%{http_code}\n' -H 'Metadata-Flavor: Google' $url
# Denied attempts are logged with the offending uid: journalctl -k -g metadata-server
let
  metadataServer = "169.254.169.254";
  dnsPort = 53;
  rootUid = 0;
in
{
  networking.nftables = {
    enable = true;
    tables.metadata-server = {
      family = "ip";
      content = ''
        chain output {
          type filter hook output priority filter; policy accept;
          ip daddr ${metadataServer} tcp dport != ${toString dnsPort} meta skuid != ${toString rootUid} jump deny
        }

        chain deny {
          limit rate 6/minute log prefix "metadata-server denied: " flags skuid
          reject with tcp reset
        }
      '';
    };
  };
}
