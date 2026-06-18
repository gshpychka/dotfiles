{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.sops-keygen;
in
{
  options.my.sops-keygen = {
    enable = lib.mkEnableOption "SSH host key + age key generation for sops-nix";

    sshKeyPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/ssh/ssh_host_ed25519_key";
      description = "SSH host ed25519 key; sops derives its age identity from this (sops.age.sshKeyPaths)";
    };

    ageKeyDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.system.primaryUserHome}/Library/Application Support/sops/age";
      description = "Directory for the age key used by the `sops` CLI (sops-nix itself decrypts via sshKeyPath)";
    };
  };

  config = lib.mkIf cfg.enable {
    # mkBefore runs this ahead of sops-install-secrets (postActivation mkAfter):
    # the host key must exist before sops decrypts.
    system.activationScripts.postActivation.text = lib.mkBefore ''
      SSH_KEY_PATH="${cfg.sshKeyPath}"
      AGE_KEY_DIR="${cfg.ageKeyDir}"
      AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"

      if ! [ -s "$SSH_KEY_PATH" ]; then
        mkdir -p "$(dirname "$SSH_KEY_PATH")"
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N ""
      fi

      if ! [ -s "$AGE_KEY_FILE" ]; then
        mkdir -p "$AGE_KEY_DIR"
        ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i "$SSH_KEY_PATH" > "$AGE_KEY_FILE"
        chmod 700 "$AGE_KEY_DIR"
        chmod 600 "$AGE_KEY_FILE"
        chown -R ${config.system.primaryUser}:staff "$AGE_KEY_DIR"
      fi

      # recipient for .sops.yaml eve_host on a fresh host
      ${pkgs.age}/bin/age-keygen -y "$AGE_KEY_FILE" > /var/log/sops-keygen.log 2>&1 || true
    '';
  };
}
