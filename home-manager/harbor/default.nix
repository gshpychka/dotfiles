{ config, ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${config.my.user} =
      { ... }:
      {
        imports = [ ../common ];
        home.stateVersion = "22.11";
      };
  };
}
