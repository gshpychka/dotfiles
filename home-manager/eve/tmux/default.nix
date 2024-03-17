{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.tmux = {
    enable = true;
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 10000;
    keyMode = "vi";
    disableConfirmationPrompt = true;
    # TODO: set up tmuxinator
    # tmuxinator.enable = true;
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = tilish;
        extraConfig = "set -g @tilish-navigator 'on'";
      }
      {
        plugin = prefix-highlight;
        # TODO: gruvbox colors
        extraConfig = "
          set -g @prefix_highlight_fg 'white'
          set -g @prefix_highlight_bg 'blue'
        ";
      }
    ];
    extraConfig = lib.concatStringsSep "\n" (
      map lib.fileContents [
        ./tmux.conf
        ./gruvbox-dark.conf
        ./status.conf
      ]
    );
  };
}
