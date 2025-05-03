{
  ...
}:
{
  programs = {
    ssh = {
      enable = true;
      matchBlocks = {
        all-remote = {
          host = "* !*.lan";
          setEnv = {
            # avoid compatibility issues
            TERM = "xterm-256color";
          };
        };
        local = {
          host = "*.lan";
          extraOptions = {
            ForwardAgent = "yes";
          };
        };
        harbor = {
          host = "harbor.lan";
          user = "pi";
        };
        reaper = {
          host = "reaper.lan";
          user = "gshpychka";
        };
        hoard = {
          host = "hoard.lan";
          user = "gshpychka";
        };
      };
    };
  };
}
