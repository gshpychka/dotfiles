{
  config,
  ...
}:
{
  systemd = {
    slices = {
      media = {
        sliceConfig = {
          IOAccounting = "yes";
          IODeviceWeight = "/mnt/hoard 10";
        };
        unitConfig = {
          RequiresMountsFor = [
            "/mnt/oasis"
            "/mnt/hoard"
          ];
        };
      };
      system-samba = {
        # extend existing slice
        unitConfig = {
          RequiresMountsFor = [
            "/mnt/hoard"
          ];
        };
        sliceConfig = {
          IOAccounting = "yes";
          IODeviceWeight = "/mnt/hoard 100";
        };
      };
    };
    services = {
      sabnzbd = {
        serviceConfig = {
          Slice = "media.slice";
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = "6";
        };
      };
      qbittorrent = {
        serviceConfig = {
          Slice = "media.slice";
          IOSchedulingClass = "idle";
        };
      };
      plex = {
        unitConfig = {
          RequiresMountsFor = [ "/mnt/hoard" ];
        };
        serviceConfig = {
          IODeviceWeight = "/mnt/hoard 1200";
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = "2";
        };
      };
      radarr.serviceConfig = {
        Slice = "media.slice";
        IOSchedulingClass = "idle";
      };
      sonarr.serviceConfig = {
        Slice = "media.slice";
        IOSchedulingClass = "idle";
      };
      lidarr.serviceConfig = {
        Slice = "media.slice";
        IOSchedulingClass = "idle";
      };
      prowlarr.serviceConfig = {
        Slice = "media.slice";
        IOSchedulingClass = "idle";
      };
    };
  };
}