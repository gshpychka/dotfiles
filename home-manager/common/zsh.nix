{
  pkgs,
  lib,
  ...
}:
{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[➜](bold green) ";
        error_symbol = "[✗](bold red) ";
      };

      directory = {
        # disable directory when in a git repo
        repo_root_style = "";
        before_repo_root_style = "";
        repo_root_format = "";
      };

      custom =
        let
          # display a host-specific icon for git repos
          generateGitHostIconModule = host: symbol: color: {
            when = "${pkgs.git}/bin/git config --get remote.origin.url | grep -q ${host}";
            require_repo = true;
            command = "";
            style = color;
            symbol = symbol;
            description = "Custom icon for ${host}";
          };
        in
        {
          github = generateGitHostIconModule "github" " " "#4078c0";
          gitlab = generateGitHostIconModule "gitlab" " " "#fc6d26";
          repo_name = {
            description = "Name of the current git repository";
            command =
              "basename \"$(${pkgs.git}/bin/git config --get remote.origin.url)\"" + "| sed 's/\.git$//'";
            # no space after
            format = "[$symbol($output)]($style)";
            when = true;
            require_repo = true;
          };
          git_directory = {
            description = "directory relative to the root of the git repo";
            # strip the last slash
            command = "${pkgs.git}/bin/git rev-parse --show-prefix | sed 's:/*$::'";
            when = true;
            require_repo = true;
            format = "[$symbol($output) ]($style)";
            symbol = "/";
            style = "bold cyan";
          };
        };

      env_var = {
        NODE_ENV = {
          variable = "NODE_ENV";
          # TODO: style brackets and contents
          format = "<[$env_value]($style)> ";
          style = "white";
        };
        AWS_PROFILE = {
          variable = "AWS_PROFILE";
          format = "[$env_value $symbol]($style) ";
          symbol = " ";
          style = "#FF9900"; # AWS orange
        };
      };

      nix_shell = {
        # just the symbol
        format = "[$symbol ]($style)";
        style = "#7EBAE4";
        symbol = "󱄅 ";
      };

      hostname = {
        ssh_only = false;
        format = "[$hostname]($style)";
      };

      # this seems to be the only way to move "custom" to the top
      format = builtins.concatStringsSep "" [
        "$directory"
        "$\{custom.github}"
        "$\{custom.gitlab}"
        "$\{custom.repo_name}"
        "$\{custom.git_directory}"
        "$git_branch"
        "$git_state"
        "$git_status"
        "$docker_context"
        "$lua"
        "$python"
        "$terraform"
        "$nix_shell"
        "$\{env_var.NODE_ENV}"
        "$sudo"
        "$character"
      ];
      right_format = builtins.concatStringsSep "" [
        "$\{env_var.AWS_PROFILE}"
        "$hostname"
      ];
    };
  };

  # pretty ls
  programs.lsd = {
    enable = true;
    enableZshIntegration = true;
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

    shellAliases = lib.mkMerge [
      {
        # cd to the root of the git repo
        cdr = "cd $(git rev-parse --show-toplevel)";
        docker-clean = "docker rmi -f $(docker images -aq) && docker volume prune -f";
      }
      (lib.mkIf pkgs.stdenv.isDarwin {
        dns-flush = lib.mkIf pkgs.stdenv.isDarwin "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";
      })
      # TODO: make these work from any directory
      (lib.mkIf pkgs.stdenv.isLinux {
        ns = "sudo nixos-rebuild switch --flake ~/dotfiles";
      })
      (lib.mkIf pkgs.stdenv.isDarwin {
        ns = "darwin-rebuild switch --flake ~/dotfiles";
      })
    ];

    initContent = ''
      bindkey '^E' autosuggest-accept

      # delete past insert start in insert mode
      bindkey -M viins '^?' backward-delete-char # If Backspace sends DEL (127)
      bindkey -M viins '^H' backward-delete-char # If Backspace sends Ctrl-H

      function cd() {
        builtin cd "$@" && ${pkgs.lsd}/bin/lsd
      }

      nixp() {
        local packages=()
        for pkg in "$@"; do
            packages+=("github:NixOS/nixpkgs#$pkg")
        done
        # needed because it doesn't respect the system-wide config
        NIXPKGS_ALLOW_UNFREE=1 nix shell --impure "''${packages[@]}"
      }

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
        src = "${pkgs.zsh-nix-shell}/share/zsh-nix-shell";
      }
    ];
  };
}
