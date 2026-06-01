{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.terminfo;
in
{
  options.my.terminfo = {
    enable = lib.mkEnableOption "additional terminfo databases";
  };

  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/config/terminfo.nix
  # https://ghostty.org/docs/help/terminfo

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      tmux.terminfo
      # ncurses provides tmux-direct (not shipped by tmux.terminfo)
      ncurses
      # the source ghostty package isn't supported on darwin; ghostty-bin is
      (if stdenv.isDarwin then ghostty-bin.terminfo else ghostty.terminfo)
    ];
  };
}

