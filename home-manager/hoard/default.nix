{ config, ... }:
{
  home-manager = {
    users.${config.my.user} =
      { ... }:
      {
        imports = [
          ../common
          ../common/tmux
          ../common/neovim
        ];
        home.stateVersion = "24.11";
      };
  };
}
