{
  ...
}:
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
}

