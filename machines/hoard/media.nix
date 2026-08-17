{
  config,
  pkgs,
  ...
}:
let
  inherit (import ./ports.nix { inherit config; }) ports;
in
{
  services = {
    plex = {
      enable = true;
      openFirewall = true;
      group = "media";
    };

    jellyfin = {
      enable = true;
      group = "media";
    };
  };

  systemd.services.plex = {
    path = [
      pkgs.curl
      pkgs.coreutils
    ];
    # Activation ends when the API answers.
    postStart = ''
      for _ in $(seq 60); do
        curl -sf -o /dev/null http://127.0.0.1:${toString ports.plex}/identity && exit 0
        sleep 1
      done
      echo "plex did not answer on port ${toString ports.plex}"
      exit 1
    '';
  };
}
