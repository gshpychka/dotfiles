{
  config,
  ...
}:
{
  my.rustdesk-server = {
    enable = true;
    # This address is handed to clients verbatim, and the firewall only
    # accepts connections on the Tailscale interface - so every client must
    # resolve it to harbor's Tailscale address (tailnet MagicDNS). If
    # MagicDNS is off on a client, replace this with harbor's Tailscale IP
    # (`tailscale ip -4` on harbor).
    relayHosts = [ config.networking.hostName ];
    privateKeyFile = config.sops.secrets.rustdesk-private-key.path;
    tailscaleOnly = true;
  };

  # Client setup (RustDesk -> Settings -> Network -> ID/Relay server):
  #   ID server: harbor (or harbor's Tailscale IP, see above)
  #   Relay server: leave empty - the signal server advertises it
  #   Key: 7gl/siUhUB1ucVatf6aiXg5BGzE+RWfl+a/uY2JQKMU=
  #
  # To generate a keypair:
  # nix-shell -p rustdesk-server --run "rustdesk-utils genkeypair"
  # echo "PRIVATE_KEY" > secrets/harbor/rustdesk-private-key.enc
  # sops -e -i secrets/harbor/rustdesk-private-key.enc
  sops.secrets.rustdesk-private-key = {
    sopsFile = ../../secrets/harbor/rustdesk-private-key.enc;
    format = "binary";
  };
}
