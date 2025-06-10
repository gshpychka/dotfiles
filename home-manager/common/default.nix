{ pkgs, ... }:
{
  imports = [
    ./zsh.nix
    ./git.nix
    ./direnv.nix
    ./ssh.nix
    ../modules/neovim
  ];

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
        color_theme = "${pkgs.btop}/share/btop/themes/gruvbox_dark_v2.theme";
        vim_keys = true;
        update_ms = 100;
        proc_tree = true;
        disks_filter = "exclude=/boot";
        io_mode = true;
        net_download = 1000;
        net_upload = 1000;
        net_auto = false;
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

  my.neovim = {
    enable = true;
    languages = [
      "bash"
      "docker"
      "json"
      "lua"
      "nix"
      "python"
      "typescript"
      "yaml"
      "zig"
    ];
  };
}
