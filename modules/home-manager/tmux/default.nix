{ config, lib, ... }:
let
  cfg = config.my.tmux;
in
{
  options.my.tmux = {
    enable = lib.mkEnableOption "Tmux terminal multiplexer";
  };

  config = lib.mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      mouse = true;
      baseIndex = 1;
      escapeTime = 0;
      historyLimit = 1000000;
      keyMode = "vi";
      disableConfirmationPrompt = true;
      # would be cooler to use "tmux-direct" but zsh can't handle it
      # we still get 16M colors via config
      terminal = "tmux-256color";
      extraConfig = lib.concatStringsSep "\n" (
        map lib.fileContents [
          ./gruvbox-dark.conf
          ./status.conf
          ./tmux.conf
          ./vim-tmux-navigator.conf
        ]
      );
    };
  };
}
