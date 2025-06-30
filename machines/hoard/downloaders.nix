{
  ...
}:
{
  services = {
    qbittorrent = {
      enable = true;
      group = "media";
    };
    sabnzbd = {
      enable = true;
      group = "media";
    };
  };
  networking.firewall.allowedTCPPorts = [
    54545 # qbittorrent
  ];
}

