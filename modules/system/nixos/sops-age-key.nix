{
  pkgs,
  ...
}:
{
  # Derive age key from SSH host key for sops CLI usage
  system.activationScripts.sopsAgeKey = {
    deps = [ "etc" ]; # ensure SSH host keys exist
    text = ''
      mkdir -p /root/.config/sops/age
      ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /root/.config/sops/age/keys.txt
      chmod 600 /root/.config/sops/age/keys.txt
    '';
  };
}
