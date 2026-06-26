{
  config,
  lib,
  ...
}:
{
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = lib.mkForce [ ]; # Override default Darwin SSH keys for GPG
    gnupg.home = "${config.system.primaryUserHome}/.gnupg";
    secrets.nixbuild-ssh-key = {
      sopsFile = ../../secrets/eve/nixbuild-ssh-key.pem;
      format = "binary";
    };
  };
}
