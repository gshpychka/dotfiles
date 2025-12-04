{
  config,
  lib,
  ...
}:
let
  inherit ((import ../ports.nix { inherit config; })) ports;
in
{
  users = {
    groups = {
      maintainerr = {
        gid = 994;
      };
      media = {
        # we need there to be a GID, but we don't care which one
        gid = lib.mkDefault 993;
      };
    };
    users = {
      maintainerr = {
        uid = 994;
        group = config.users.groups.maintainerr.name;
        extraGroups = [ config.users.groups.media.name ];
        isSystemUser = true;
      };
    };
  };
  virtualisation.oci-containers.containers.maintainerr = {
    image = "ghcr.io/maintainerr/maintainerr:2.22";
    volumes = [
      "/var/lib/maintainerr:/opt/data"
    ];
    environment = {
      TZ = config.time.timeZone;
      UI_PORT = ports.maintainerr;
      UI_HOST = "127.0.0.1";
    };
    # need to refer by ID because these names don't exist in the container
    user = "${toString config.users.users.maintainerr.uid}:${toString config.users.groups.maintainerr.gid}";
    extraOptions = [
      # host networking to give us access to localhost
      # this also means we don't need to map ports
      "--network=host"
      # secondary group for the user
      "--group-add=${toString config.users.groups.media.gid}"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/maintainerr 0755 ${config.users.users.maintainerr.name} ${config.users.groups.maintainerr.name} -"
  ];
}
