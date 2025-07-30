{ config, pkgs, ... }:
{
  home-manager = {
    users.${config.my.user} =
      { ... }:
      {
        imports = [
          ../../modules/home-manager
        ];

        my = {
          ai.enable = true;
          btop.enable = true;
          direnv.enable = true;
          git.enable = true;
          neovim.enable = true;
          nh.enable = true;
          ssh.enable = true;
          tmux.enable = true;
          tools.enable = true;
          zsh.enable = true;
        };

        home.packages = with pkgs; [ ];

        home.stateVersion = "24.05";
      };
  };
}
