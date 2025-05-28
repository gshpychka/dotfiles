{
  ...
}:
{
  programs = {
    ssh = {
      enable = true;
      matchBlocks = {
        all-remote = {
          host = "* !*.lan !*.glib.sh";
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
      };
    };
  };
}
