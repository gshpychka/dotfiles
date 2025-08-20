# based on https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/ssh/sshd.nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.openssh;
in
{
  options.services.openssh = {
    hostKeys = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [
        {
          type = "rsa";
          bits = 4096;
          path = "/etc/ssh/ssh_host_rsa_key";
        }
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];
      description = ''
        NixOS-compatible SSH host key generation for nix-darwin.
        Generates host keys if they don't exist.
      '';
    };
  };

  config = lib.mkIf (cfg.hostKeys != [ ]) {
    # launchd service to generate keys on boot, similar to systemd sshd-keygen
    launchd.daemons.ssh-keygen = {
      script = lib.flip lib.concatMapStrings cfg.hostKeys (k: ''
        if ! [ -s "${k.path}" ]; then
          if ! [ -h "${k.path}" ]; then
            rm -f "${k.path}"
          fi
          mkdir -p "$(dirname '${k.path}')"
          chmod 0755 "$(dirname '${k.path}')"
          ${pkgs.openssh}/bin/ssh-keygen \
            -t "${k.type}" \
            ${lib.optionalString (k ? bits) "-b ${toString k.bits}"} \
            ${lib.optionalString (k ? comment) "-C '${k.comment}'"} \
            ${lib.optionalString (k ? openSSHFormat && k.openSSHFormat) "-o"} \
            -f "${k.path}" \
            -N ""
        fi
      '');
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = false; # like OneShot
        StandardOutPath = "/var/log/ssh-keygen.log";
        StandardErrorPath = "/var/log/ssh-keygen.log";
      };
    };
  };
}
