{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.tmux = {
    enable = true;
    shortcut = "o";
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 10000;
    keyMode = "vi";
    disableConfirmationPrompt = true;
    terminal = "screen-256color";
    tmuxinator.enable = true;
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = gruvbox;
        extraConfig = "set -g @tmux-gruvbox 'dark'";
      }
      tmux-fzf
      {
        plugin = tilish;
        extraConfig = "set -g @tilish-navigator 'on'";
      }
    ];
    extraConfig = lib.strings.fileContents ./tmux.conf;
  };
}
