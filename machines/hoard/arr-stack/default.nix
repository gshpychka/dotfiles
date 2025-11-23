{
  ...
}:
{
  imports = [
    ./recyclarr.nix
  ];

  services = {
    prowlarr = {
      enable = true;
    };
    sonarr = {
      enable = true;
      group = "media";
    };
    radarr = {
      enable = true;
      group = "media";
    };
    lidarr = {
      enable = true;
      group = "media";
    };
    bazarr = {
      enable = true;
      group = "media";
    };
    overseerr = {
      enable = true;
    };
  };
}