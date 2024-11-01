{
  pkgs,
  lib,
  ...
}: {
  programs.tmux = {
    enable = true;
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 1000000;
    keyMode = "vi";
    disableConfirmationPrompt = true;
    # TODO: set up tmuxinator
    # tmuxinator.enable = true;
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = tilish;
        extraConfig = "set -g @tilish-navigator 'on'";
      }
    ];
    extraConfig = lib.concatStringsSep "\n" (
      map lib.fileContents [
        ./gruvbox-dark.conf
        ./status.conf
        ./tmux.conf
      ]
    );
  };
}
