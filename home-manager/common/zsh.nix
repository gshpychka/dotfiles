{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.starship = {
    enable = true;
    enableNushellIntegration = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[➜](bold green) ";
        error_symbol = "[✗](bold red) ";
      };
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autocd = true;
    dotDir = ".config/zsh";
    defaultKeymap = "viins";
    autosuggestion = {
      enable = true;
    };

    history = {
      expireDuplicatesFirst = true;
      ignoreDups = true;
      ignoreSpace = true; # ignore commands starting with a space
      save = 20000;
      size = 20000;
      share = true;
    };
    historySubstringSearch = {
      enable = true;
    };

    shellAliases = {
      # cd to the root of the git repo
      cdr = "cd $(git rev-parse --show-toplevel)";
    };

    initExtra = ''
      bindkey '^l' autosuggest-accept

      function cd() {
        builtin cd $*
        ${pkgs.lsd}/bin/lsd
      }

      function nf() {
        darwin-rebuild switch --flake ~/.nixpkgs
      }
      if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
        exec tmux
      fi

    '';

    plugins = [
      {
        name = "fast-syntax-highlighting";
        file = "fast-syntax-highlighting.plugin.zsh";
        src = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions";
      }
      {
        name = "zsh-nix-shell";
        file = "nix-shell.plugin.zsh";
        src = pkgs.fetchFromGitHub {
          owner = "chisui";
          repo = "zsh-nix-shell";
          rev = "v0.8.0";
          sha256 = "Z6EYQdasvpl1P78poj9efnnLj7QQg13Me8x1Ryyw+dM=";
        };
      }
    ];
    # prezto = {
    #   enable = true;
    #   caseSensitive = false;
    #   utility.safeOps = true;
    #   editor = {
    #     dotExpansion = true;
    #     keymap = "vi";
    #   };
    #   #prompt.showReturnVal = true;
    #   #tmux.autoStartLocal = true;
    #   pmodules = [
    #     "autosuggestions"
    #     "completion"
    #     "directory"
    #     "editor"
    #     "git"
    #     "terminal"
    #   ];
    # };
  };
}
