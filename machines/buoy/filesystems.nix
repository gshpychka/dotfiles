{
  config,
  ...
}:
{
  imports = [ ./data-disk.nix ];

  # state directories go onto persistent disk
  fileSystems."/var/lib" = {
    # directory created by the bootstrap image
    # (dataDirectoriesToBootstrap in infra/nixos/configuration.nix)
    device = "${config.fileSystems.data.mountPoint}/var-lib";
    fsType = "none";
    options = [ "bind" ];
    depends = [ config.fileSystems.data.mountPoint ];
  };
}
