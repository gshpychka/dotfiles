{
  config,
  pkgs,
  ...
}: {
  imports = [
    # ./linkapps.nix
    ./finicky
    ./ghostty
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
        everything = {
          host = "* !*.lan";
          setEnv = {
            TERM = "xterm-256color";
          };
        };
        local = {
          host = "*.lan";
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

  modules.ghostty.enable = true;
}
