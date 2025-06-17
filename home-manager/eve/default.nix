{
  pkgs,
  config,
  ...
}:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${config.my.user} =
      { ... }:
      {
        imports = [
          ./finicky
          ./ghostty.nix
          ./alacritty.nix
          ./1password.nix
          ./npm.nix
          ../common/tmux
          ../common/neovim
          ../common
        ];
        home = {
          file.".hushlogin".text = "";

          stateVersion = "22.11";
          packages = with pkgs; [
            yubikey-manager
            gnupg
            pinentry_mac
            sops
          ];
        };
      };
  };
}
