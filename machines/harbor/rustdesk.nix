{
  config,
  ...
}:
{
  my.rustdesk-server = {
    enable = true;
    # Harbor's Tailscale IP (check with: tailscale ip -4)
    relayHosts = [ config.networking.hostName ];
    privateKeyFile = config.sops.secrets.rustdesk-private-key.path;
    tailscaleOnly = true;
  };

  # Public key (for client configuration):
  # 7gl/siUhUB1ucVatf6aiXg5BGzE+RWfl+a/uY2JQKMU=
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
