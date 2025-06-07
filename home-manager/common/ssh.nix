{
  config,
  ...
}:
{
  imports = [
    ../../modules/globals.nix
  ];
  programs = {
    ssh = {
      enable = true;
      extraConfig = ''
        CanonicalizeHostname always
        CanonicalDomains ${config.my.domain}
      '';
      matchBlocks = {
        all-remote = {
          host = "* !*.${config.my.domain}";
          setEnv = {
            # avoid compatibility issues
            TERM = "xterm-256color";
          };
        };
        local = {
          host = "*.${config.my.domain}";
          extraOptions = {
            ForwardAgent = "yes";
          };
        };
        harbor = {
          host = "harbor.${config.my.domain}";
          user = "pi";
        };
        reaper = {
          host = "reaper.${config.my.domain}";
          user = "gshpychka";
        };
        hoard = {
          host = "hoard.${config.my.domain}";
          user = "gshpychka";
        };
        kodi = {
          host = "kodi.${config.my.domain}";
          user = "root";
          setEnv = {
            TERM = "xterm-256color";
          };
        };
      };
    };
  };
}
