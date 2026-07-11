{
  config,
  ...
}:
{
  # All service ports in one place, as integers, referencing the owning
  # module's option wherever one exists.
  ports = {
    glances = config.services.glances.port;
    qbittorrent = config.services.qbittorrent.webuiPort;
    home = config.services.homepage-dashboard.listenPort;
    # sabnzbd's port lives in its stateful sabnzbd.ini
    sabnzbd = 8085;
    sonarr = config.services.sonarr.settings.server.port;
    radarr = config.services.radarr.settings.server.port;
    lidarr = config.services.lidarr.settings.server.port;
    prowlarr = config.services.prowlarr.settings.server.port;
    bazarr = config.services.bazarr.listenPort;
    overseerr = config.services.overseerr.port;
    maintainerr = 6246;
    tautulli = config.services.tautulli.port;
    # fixed upstream
    plex = 32400;
    # Jellyfin's default HTTP port; not exposed as a module option
    jellyfin = 8096;
  };
}
