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

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Ghostty terminfo for SSH sessions from eve
      ghostty.terminfo
    ];
  };
}