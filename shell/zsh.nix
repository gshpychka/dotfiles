{ config, pkgs, lib, ... }: {

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
    enableAutosuggestions = true;
    enableCompletion = true;
    autocd = true;
    dotDir = ".config/zsh";
    #defaultKeymap = "viins"; #vicmd or viins
    
    history = {
      expireDuplicatesFirst = true;
      ignoreDups = true;
      ignoreSpace = true; # ignore commands starting with a space
      save = 20000;
      size = 20000;
      share = true;
    };

    initExtra = ''
      # fixes starship swallowing newlines
      precmd() {
        precmd() {
          echo
        }
      }

      #export LD_LIBRARY_PATH=${lib.makeLibraryPath [pkgs.stdenv.cc.cc]}

      # this is backspace
      bindkey '^H' autosuggest-accept

      bindkey '^r' fzf-history-widget
      bindkey '^t' fzf-file-widget
      bindkey 'ç' fzf-cd-widget

      function cd() {
        builtin cd $*
        lsd
      }

      function nf() {
        darwin-rebuild switch --flake ~/.nixpkgs
      }
    '';

    # TODO: figure out how to access
    # initExtraBeforeCompInit = ''
    #   eval "$(${.homebrew.brewPrefix}/brew shellenv)"
    # '';
    initExtraBeforeCompInit = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';

    dirHashes = {
      nix = "$HOME/.nixpkgs";
      mm = "$HOME/projects/alpha/mm";
    };

    plugins = [
      {
        name = "fast-syntax-highlighting";
        file = "fast-syntax-highlighting.plugin.zsh";
        src = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions";
      }
      {
        name = "zsh-nix-shell";
        file = "nix-shell.plugin.zsh";
        src = "${pkgs.zsh-nix-shell}/share/zsh-nix-shell";
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
