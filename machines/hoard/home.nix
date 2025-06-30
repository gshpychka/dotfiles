{ config, ... }:
{
  home-manager = {
    users.${config.my.user} =
      { ... }:
      {
        imports = [
          ../../modules/home-manager
        ];

        my = {
          tmux.enable = true;
          btop.enable = true;
          git.enable = true;
          neovim.enable = true;
          ssh.enable = true;
          tools.enable = true;
          zsh.enable = true;
        };

        home.stateVersion = "24.11";
      };
  };
}
