{
  config,
  lib,
  ...
}:
{
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = lib.mkForce [ ]; # Override default Darwin SSH keys for GPG
    # the host key above decrypts every secret deployed here; a configured gnupg
    # home makes sops fall back to the YubiKey and block activation on pinentry
    gnupg.home = null;
    secrets.nixbuild-ssh-key = {
      sopsFile = ../../secrets/eve/nixbuild-ssh-key.pem;
      format = "binary";
    };
  };
}
