{pkgs, ...}: {
  imports = [./zsh.nix ./git.nix ./direnv.nix];

  home = {
    preferXdgDirectories = true;
    packages = with pkgs; [
      gh # github cli tool
      fd
    ];
  };

  programs = {
    # let home-manager manage itself
    home-manager.enable = true;

    jq.enable = true;
    bat = {
      # pretty cat
      enable = true;
      config = {
        theme = "gruvbox-dark";
      };
    };
    btop = {
      enable = true;
      settings = {
        color_theme = "${pkgs.btop}/share/btop/themes/gruvbox_dark.theme";
        vim_keys = true;
      };
    };

    fzf = {
      enable = true;
      fileWidgetCommand = "${pkgs.fd}/bin/fd --type f --strip-cwd-prefix";
      changeDirWidgetCommand = "${pkgs.fd}/bin/fd --type d --strip-cwd-prefix";
      defaultOptions = [
        "--border sharp"
        "--inline-info"
        "--bind ctrl-h:preview-down,ctrl-l:preview-up"
      ];
    };
  };
}
