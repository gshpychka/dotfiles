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
          btop.enable = true;
          git.enable = true;
          ssh.enable = true;
          tools.enable = true;
          zsh.enable = true;
        };

        home.stateVersion = "22.11";
      };
  };
}
