# The agent's own age key, generated on this host, which sops in its commands
# decrypts with.
#
# Imperative, one-time: add the key's public half to .sops.yaml:
#   sudo grep '^# public key' /var/lib/openclaw/age-key.txt
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;

  # the private key exists only on this host
  generateKey = pkgs.writeShellScript "openclaw-generate-age-key" ''
    set -euo pipefail
    [ -e ${cfg.ageKeyFile} ] || ${lib.getExe' pkgs.age "age-keygen"} -o ${cfg.ageKeyFile}
  '';
in
{
  options.my.openclaw.ageKeyFile = lib.mkOption {
    type = lib.types.str;
    default = "${gw.stateDir}/age-key.txt";
    readOnly = true;
    description = "The agent's own age key.";
  };

  config = lib.mkIf cfg.enable {
    services.openclaw-gateway = {
      environment.SOPS_AGE_KEY_FILE = cfg.ageKeyFile;
      execStartPre = [ "${generateKey}" ];
    };

    my.openclaw = {
      extraPackages = with pkgs; [
        sops
        age
      ];
      skills.secrets = {
        description = "Read and write sops secrets encrypted to your own age key, in a checkout of the owner's dotfiles.";
        text = ''
          `sops` decrypts with your own age key, which never leaves this host.
          In a checkout of the owner's dotfiles, files under `secrets/openclaw/`
          are encrypted to you and to the owner, and new files there get the
          right keys from `.sops.yaml`:

          - `sops decrypt secrets/openclaw/<file>` reads one;
          - `sops set secrets/openclaw/<file> '["<key>"]' '"<value>"'` adds or
            changes a value.

          A decrypted value enters your context and goes to the model
          provider: decrypt only what the task needs, and never repeat a
          secret value in a reply.
        '';
      };
    };
  };
}
