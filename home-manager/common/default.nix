{
  config,
  pkgs,
  lib,
  inputs,
  system,
  ...
}: {
  imports = [./zsh.nix];

  home = {
    packages = with pkgs; [
      ripgrep # fast search
      gh # github cli tool
      fd
      #_1password # CLI
    ];

    # sessionPath = [
    # "$HOME/go/bin"
    # "$HOME/.local/bin"
    # "$HOME/.cargo/bin"
    # ];
    # sessionVariables = {
    # VISUAL = "nvim";
    # };
  };

  programs = {
    # let home-manager manage itself
    home-manager.enable = true;

    # shell integrations are enabled by default
    jq.enable = true; # json parser
    bat.enable = true; # pretty cat
    # lazygit.enable = true; # git tui
    # nnn.enable = true; # file browser

    # pretty ls
    lsd = {
      enable = true;
      enableAliases = true;
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

    fzf = let
      fdOpts = "--exclude node_modules --exclude .git --exclude .cache";
    in {
      enable = true;
      defaultCommand = "${pkgs.fd}/bin/fd --type f --hidden --follow " + fdOpts;
      changeDirWidgetCommand = "${pkgs.fd}/bin/fd --type d " + fdOpts;
      tmux.enableShellIntegration = true;
      defaultOptions = [
        "--border sharp"
        "--inline-info"
        "--bind ctrl-h:preview-down,ctrl-l:preview-up"
      ];
    };
  };
}
