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
      ghostty.terminfo
      tmux.terminfo
    ];
  };
}

