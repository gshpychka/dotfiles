{
  config,
  lib,
  pkgs,
  ...
}:
let
  # sops-install-secrets runs unattended, so a missing YubiKey must fail fast
  # rather than pop a pinentry asking for it; with a card present gpg behaves
  # normally, including the PIN dialog
  gpgCardGated = pkgs.writeShellScriptBin "gpg" ''
    if ${pkgs.gnupg}/bin/gpg-connect-agent --quiet 'SCD SERIALNO' /bye 2>/dev/null | grep -q '^S SERIALNO'; then
      exec ${pkgs.gnupg}/bin/gpg "$@"
    fi
    exec ${pkgs.gnupg}/bin/gpg --pinentry-mode error "$@"
  '';
in
{
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = lib.mkForce [ ]; # Override default Darwin SSH keys for GPG
    gnupg.home = "${config.system.primaryUserHome}/.gnupg";
    # sops-nix only takes bin/gpg from this package, via SOPS_GPG_EXEC
    gnupg.package = pkgs.symlinkJoin {
      name = "gnupg-card-gated";
      paths = [
        gpgCardGated
        pkgs.gnupg
      ];
    };
    secrets.nixbuild-ssh-key = {
      sopsFile = ../../secrets/eve/nixbuild-ssh-key.pem;
      format = "binary";
    };
  };
}
