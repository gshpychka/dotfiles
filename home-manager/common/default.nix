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
    ];
  };

  programs = {
    # let home-manager manage itself
    home-manager.enable = true;

    # shell integrations are enabled by default
    jq.enable = true; # json parser
    bat.enable = true; # pretty cat
    # lazygit.enable = true; # git tui
    # nnn.enable = true; # file browser

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
      fileWidgetCommand = "${pkgs.fd}/bin/fd --type f --strip-cwd-prefix";
      changeDirWidgetCommand = "${pkgs.fd}/bin/fd --type d --strip-cwd-prefix";
      tmux.enableShellIntegration = true;
      defaultOptions = [
        "--border sharp"
        "--inline-info"
        "--bind ctrl-h:preview-down,ctrl-l:preview-up"
      ];
    };
  };
}
