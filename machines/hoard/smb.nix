{
  config,
  ...
}:
{
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      # https://www.samba.org/samba/docs/current/man-html/vfs_fruit.8.html
      global = {
        "fruit:aapl" = "yes";
        "fruit:nfs_aces" = "no";
      };
      "time-machine" = {
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:time machine" = "yes";
        "fruit:time machine max size" = "2T";
        "fruit:metadata" = "stream";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:nfs_aces" = "no";
        "path" = "/mnt/hoard/shares/time-machine";
        "valid users" = config.users.users.time-machine.name;
        "public" = "no";
        "writeable" = "yes";
      };
      "kodi" = {
        "path" = "/mnt/hoard/plex";
        "valid users" = config.users.users.kodi.name;
        "public" = "no";
        "writable" = "yes";
      };
    };
  };
}