{pkgs, ...}: {
  imports = [./zsh.nix ./git.nix ./direnv.nix];

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

    btop = {
      enable = true;
      settings = {
        # TODO: not working?
        color_theme = "${pkgs.btop}/share/btop/themes/gruvbox_dark.theme";
        vim_keys = true;
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
