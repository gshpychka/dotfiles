{
  config,
  ...
}:
{
  virtualisation = {
    oci-containers.backend = "docker";
    docker = {
      enable = true;
      storageDriver = "overlay2";
      autoPrune.enable = true;
    };
  };
}
