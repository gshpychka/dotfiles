{
  config,
  ...
}:
{
  services = {
    qbittorrent = {
      enable = true;
      group = "media";
      # state layout predates the upstream module's /var/lib/qBittorrent default
      profileDir = "/var/lib/qbittorrent";
      torrentingPort = 54545;
    };
    sabnzbd = {
      enable = true;
      group = "media";
    };
  };

  # uid was pinned by the previously vendored qbittorrent module;
  # keep it so the existing state stays owned correctly
  users.users.qbittorrent.uid = 888;

  networking.firewall.allowedTCPPorts = [
    config.services.qbittorrent.torrentingPort
  ];
}
