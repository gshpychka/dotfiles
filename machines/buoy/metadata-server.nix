# Only root reaches the GCE metadata API, which hands the VM's service-account
# token to any local process that asks.
let
  # also the VPC's DNS resolver (UDP and TCP), NTP server and DHCP server; the
  # metadata API is HTTP over TCP
  metadataServer = "169.254.169.254";
  dnsPort = 53;
  # google-guest-agent and google-{startup,shutdown}-scripts, the metadata API's
  # clients, run as root; meta skuid is the uid in the initial user namespace
  rootUid = 0;
in
{
  networking.nftables = {
    enable = true;
    tables.metadata-server = {
      # the VPC subnet is IPv4-only, so the metadata server has no IPv6 address
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
