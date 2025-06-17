{ config, ... }:
{
  home-manager = {
    users.${config.my.user} =
      { ... }:
      {
        imports = [ ../common ];
        home.stateVersion = "22.11";
      };
  };
}
