let
  inherit (import ./disks.nix) arrayMembers;
  # systemd resolves each partition to the whole disk, which is where bfq runs.
  weight = value: map (device: "${device} ${toString value}") (builtins.attrValues arrayMembers);
in
{
  systemd = {
    slices = {
      media = {
        sliceConfig = {
          IOAccounting = "yes";
          IODeviceWeight = weight 1000;
        };
        unitConfig = {
          RequiresMountsFor = [
            "/mnt/oasis"
            "/mnt/hoard"
          ];
        };
      };
      media-bulk = {
        sliceConfig = {
          IOAccounting = "yes";
          # low priority - must not affect playback
          IODeviceWeight = weight 10;
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
          IODeviceWeight = weight 100;
        };
      };
    };
    services = {
      sabnzbd = {
        serviceConfig = {
          Slice = "media-bulk.slice";
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = "6";
        };
      };
      qbittorrent = {
        serviceConfig = {
          Slice = "media-bulk.slice";
          IOSchedulingClass = "idle";
        };
      };
      plex = {
        serviceConfig = {
          Slice = "media.slice";
          IODeviceWeight = weight 1000;
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = "2";
        };
      };
      radarr.serviceConfig = {
        Slice = "media-bulk.slice";
        IOSchedulingClass = "idle";
      };
      sonarr.serviceConfig = {
        Slice = "media-bulk.slice";
        IOSchedulingClass = "idle";
      };
      lidarr.serviceConfig = {
        Slice = "media-bulk.slice";
        IOSchedulingClass = "idle";
      };
      prowlarr.serviceConfig = {
        Slice = "media-bulk.slice";
        IOSchedulingClass = "idle";
      };
    };
  };
}
