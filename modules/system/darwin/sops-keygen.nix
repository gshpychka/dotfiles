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
    enable = lib.mkEnableOption "SSH and Age key generation for sops-nix";

    sshKeyPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/ssh/ssh_host_ed25519_key";
      description = "Path to the SSH host ed25519 key";
    };

    ageKeyDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.system.primaryUserHome}/Library/Application Support/sops/age";
      description = "Directory where the age key will be stored";
    };
  };

  config = lib.mkIf cfg.enable {
    # launchd service to generate SSH key and convert to age format
    launchd.daemons.sops-keygen = {
      script = ''
        SSH_KEY_PATH="${cfg.sshKeyPath}"
        AGE_KEY_DIR="${cfg.ageKeyDir}"
        AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"

        # Generate SSH host key if it doesn't exist
        if ! [ -s "$SSH_KEY_PATH" ]; then
          mkdir -p "$(dirname '$SSH_KEY_PATH')"
          chmod 0755 "$(dirname '$SSH_KEY_PATH')"
          ${pkgs.openssh}/bin/ssh-keygen \
            -t ed25519 \
            -f "$SSH_KEY_PATH" \
            -N ""
          echo "SSH host key generated at $SSH_KEY_PATH"
        fi

        # Convert SSH key to age key if age key doesn't exist
        if ! [ -s "$AGE_KEY_FILE" ]; then
          mkdir -p "$AGE_KEY_DIR"
          chmod 700 "$AGE_KEY_DIR"
          
          # Convert SSH ed25519 key to age format
          ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i "$SSH_KEY_PATH" > "$AGE_KEY_FILE"
          chmod 600 "$AGE_KEY_FILE"
          
          echo "Age key generated from SSH key at $AGE_KEY_FILE"
        else
          echo "Age key already exists at $AGE_KEY_FILE"
        fi
        AGE_PUBLIC_KEY="$(${pkgs.age}/bin/age-keygen -y "$AGE_KEY_FILE")"
        echo "Age public key: $AGE_PUBLIC_KEY"
      '';
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = false; # like OneShot
        StandardOutPath = "/var/log/sops-keygen.log";
        StandardErrorPath = "/var/log/sops-keygen.log";
      };
    };
  };
}
