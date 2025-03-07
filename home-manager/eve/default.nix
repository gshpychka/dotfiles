{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./finicky
    ./ghostty.nix
    ./alacritty.nix
    ./1password.nix
    ./npm.nix
    ../common/tmux
    ../common/neovim
    ../common
  ];

  home = {
    packages = with pkgs; [
      yubikey-manager
    ];
  };
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
          host = "*.lan,*.local";
          extraOptions = {ForwardAgent = "yes";};
        };
        harbor = {
          host = "harbor.lan";
          user = config.shared.harborUsername;
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
    tmux = {
      # different prefix for eve to avoid conflicts
      shortcut = "n";
    };
  };
}
