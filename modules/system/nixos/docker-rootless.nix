{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  autoPrune = config.virtualisation.docker.autoPrune;
in
{
  config = mkIf config.virtualisation.docker.rootless.enable (mkMerge [
    {
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
    }

    # Applies virtualisation.docker.autoPrune's schedule to the rootless daemon.
    (mkIf autoPrune.enable {
      # Stopped containers and volumes stay, as they hold project databases.
      systemd.user.services.docker-prune = {
        description = "Prune rootless Docker images and build cache";
        requires = [ "docker.service" ];
        after = [ "docker.service" ];
        environment.DOCKER_HOST = "unix://%t/docker.sock";
        path = [ config.virtualisation.docker.rootless.package ];
        serviceConfig.Type = "oneshot";
        script = ''
          # remove images no container uses
          docker image prune --all --force
          # remove the build cache
          docker builder prune --all --force
        '';
      };

      systemd.user.timers.docker-prune = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = autoPrune.dates;
          Persistent = autoPrune.persistent;
          RandomizedDelaySec = autoPrune.randomizedDelaySec;
        };
      };
    })
  ]);
}
