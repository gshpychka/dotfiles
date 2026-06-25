{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.sops-age-key;
  # sops resolves its key file under XDG_CONFIG_HOME.
  ageDir = "${config.system.primaryUserHome}/.config/sops/age";
in
{
  # age key for interactive `sops` CLI use, derived from the SSH host key.
  # sops-nix itself decrypts via sops.age.sshKeyPaths, not this.
  options.my.sops-age-key.enable = lib.mkEnableOption "deriving the user's age key from the SSH host key for the sops CLI";

  config = lib.mkIf cfg.enable {
    system.activationScripts.postActivation.text = ''
      mkdir -p "${ageDir}"
      ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "${ageDir}/keys.txt"
      chmod 600 "${ageDir}/keys.txt"
      chown ${config.system.primaryUser}:staff "${ageDir}/keys.txt"
    '';
  };
}
