{
  ...
}:
{
  programs = {
    ssh = {
      enable = true;
      extraConfig = ''
        CanonicalizeHostname always
        CanonicalDomains glib.sh
      '';
      matchBlocks = {
        all-remote = {
          host = "* !*.glib.sh";
          setEnv = {
            # avoid compatibility issues
            TERM = "xterm-256color";
          };
        };
        local = {
          host = "*.glib.sh";
          extraOptions = {
            ForwardAgent = "yes";
          };
        };
        harbor = {
          host = "harbor.glib.sh";
          user = "pi";
        };
        reaper = {
          host = "reaper.glib.sh";
          user = "gshpychka";
        };
        hoard = {
          host = "hoard.glib.sh";
          user = "gshpychka";
        };
        kodi = {
          host = "kodi.glib.sh";
          user = "root";
          setEnv = {
            TERM = "xterm-256color";
          };
        };
      };
    };
  };
}
