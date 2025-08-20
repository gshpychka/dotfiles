{
  config,
  lib,
  ...
}:
{
  my.sops-keygen = {
    enable = true;
    sshKeyPath = "/etc/ssh/ssh_host_ed25519_key";
  };

  sops = {
    age.sshKeyPaths = [ config.my.sops-keygen.sshKeyPath ];
    gnupg.sshKeyPaths = lib.mkForce [ ]; # Override default Darwin SSH keys for GPG
    gnupg.home = "${config.system.primaryUserHome}/.gnupg";
    secrets.nixbuild-ssh-key = {
      sopsFile = ../../secrets/eve/nixbuild-ssh-key.pem;
      format = "binary";
    };
  };

}
