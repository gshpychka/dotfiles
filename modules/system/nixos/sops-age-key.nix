{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.sops-age-key;
in
{
  # This is for interactively using the sops CLI as root (e.g. editing
  # secrets); sops-nix secret decryption uses sops.age.sshKeyPaths instead.
  options.my.sops-age-key.enable = lib.mkEnableOption "deriving root's age key from the SSH host key";

  config = lib.mkIf cfg.enable {
    # Derive age key from SSH host key for sops CLI usage
    system.activationScripts.sopsAgeKey = {
      deps = [ "etc" ]; # ensure SSH host keys exist
      text = ''
        mkdir -p /root/.config/sops/age
        ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /root/.config/sops/age/keys.txt
        chmod 600 /root/.config/sops/age/keys.txt
      '';
    };
  };
}
