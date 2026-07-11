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
      # qBittorrent.conf is stateful (adopting serverConfig would overwrite
      # it wholesale). One-time UI step: Options → Web UI → "Bypass
      # authentication for clients on localhost"; every request arrives from
      # loopback (nginx or a stack service), the web gateway owns interactive
      # auth, and the loopback gate constrains local processes. Leave
      # "trusted reverse proxies" unset: the bypass must key on the socket
      # address, which is nginx on loopback.
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
