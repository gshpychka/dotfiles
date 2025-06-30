{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.tools;
in
{
  options.my.tools = {
    enable = lib.mkEnableOption "common command-line tools";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      fd
      ripgrep
      dnsutils
    ];

    programs.jq.enable = true;
  };
}

