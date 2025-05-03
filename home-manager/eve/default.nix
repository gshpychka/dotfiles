{
  pkgs,
  ...
}:
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
    packages = with pkgs; [
      yubikey-manager
      gnupg
      pinentry_mac
      sops
    ];
  };
}
