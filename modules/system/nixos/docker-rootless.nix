{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
{
  config = mkIf config.virtualisation.docker.rootless.enable {
    # rootlesskit's copy-up of /etc recreates /etc/static verbatim, freezing the
    # daemon's view of /etc at the generation live when it started. /nix is shared
    # with the host, so the system profile resolves to the generation that
    # `nixos-rebuild switch` and `boot` install.
    systemd.user.services.docker.serviceConfig.ExecStartPost =
      "${pkgs.writeShellScript "docker-rootless-pin-etc" ''
        # rootlesskit's child_pid holds the namespace with the copied-up /etc.
        exec ${pkgs.util-linux}/bin/nsenter \
          --target "$(cat "$XDG_RUNTIME_DIR/dockerd-rootless/child_pid")" \
          --mount --user --preserve-credentials \
          -- ${pkgs.coreutils}/bin/ln -sfn /nix/var/nix/profiles/system/etc /etc/static
      ''}";
  };
}
