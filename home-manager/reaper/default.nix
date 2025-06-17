{ config, ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${config.my.user} =
      { ... }:
      {
        imports = [
          ../common
          ../common/tmux
          ../common/neovim
        ];
        home.stateVersion = "24.05";
      };
  };
}
