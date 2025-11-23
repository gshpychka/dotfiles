{
  config,
  ...
}: {
  # Define all service ports in one place
  ports = {
    glances = toString config.services.glances.port;
    qbittorrent = toString config.services.qbittorrent.port;
    home = toString config.services.homepage-dashboard.listenPort;
    sabnzbd = "8085";
    sonarr = "8989";
    radarr = "7878";
    lidarr = "8686";
    prowlarr = "9696";
    bazarr = toString config.services.bazarr.listenPort;
    overseerr = toString config.services.overseerr.port;
    tautulli = toString config.services.tautulli.port;
    plex = "32400";
    jellyfin = "8096";
  };
}