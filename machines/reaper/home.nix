{ config, ... }:
{
  home-manager = {
    users.${config.my.user} =
      { ... }:
      {
        imports = [
          ../../modules/home
        ];

        my = {
          btop.enable = true;
          direnv.enable = true;
          git.enable = true;
          neovim.enable = true;
          ssh.enable = true;
          tmux.enable = true;
          tools.enable = true;
          zsh.enable = true;
        };

        home.stateVersion = "24.05";
      };
  };
}
