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
          host = "*";
          setEnv = {
            TERM = "xterm-256color";
          };
        };
        harbor = {
          host = "harbor.lan";
          user = config.shared.harborUsername;
          extraOptions = {ForwardAgent = "yes";};
        };
        reaper = {
          host = "reaper.lan";
          extraOptions = {ForwardAgent = "yes";};
          user = "gshpychka";
        };
        hoard = {
          host = "hoard.lan";
          extraOptions = {ForwardAgent = "yes";};
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
