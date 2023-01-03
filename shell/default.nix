{ config, pkgs, lib, inputs, system, ... }: {
  imports = [
    ./zsh.nix
    ./tmux.nix
    ./git.nix
  ];

  home = {
    packages = with pkgs; [
      neovim # customized by overlay

      # core
      #fd
      ripgrep # fast search

      # htop alternatives
      bottom

      #grc # colored log output
      #gitAndTools.delta # pretty diff tool
      #sshfs # mount folders via ssh
      gh # github cli tool
      #graph-easy # draw graphs in the terminal

      # programming
      python3
      poetry # python tools
      black
      rustup # rust
      nodejs
      nodePackages.npm
      nodePackages_latest.aws-cdk

      #slides # terminal presentation tool

      #_1password # CLI
    ];

    sessionPath = [
      "$HOME/go/bin"
      "$HOME/.local/bin"
      "$HOME/.cargo/bin"
    ];
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  programs = {
    # let home-manager manage itself
    home-manager.enable = true;

    # shell integrations are enabled by default
    jq.enable = true; # json parser
    bat.enable = true; # pretty cat
    lazygit.enable = true; # git tui
    nnn.enable = true; # file browser

    # pretty ls
    lsd = {
      enable = true;
      enableAliases = true;
    };

    go = {
      enable = true;
      package = pkgs.go_1_18;
      goPath = "go";
      goBin = "go/bin";
      goPrivate = [ "github.com/stackitcloud" ];
    };

    htop = {
      enable = true;
      settings = {
        tree_view = true;
        show_cpu_frequency = true;
        show_cpu_usage = true;
        show_program_path = false;
      };
    };

    fzf = {
      enable = true;
      defaultCommand = "fd --type f --hidden --follow --exclude .git --exclude .vim --exclude .cache --exclude vendor";
      defaultOptions = [
        "--border sharp"
        "--inline-info"
        "--bind ctrl-h:preview-down,ctrl-l:preview-up"
      ];
    };
  };
}
