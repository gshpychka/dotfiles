{ config, lib, ... }:
let
  cfg = config.my.ghostty;
in
{
  options.my.ghostty = {
    enable = lib.mkEnableOption "Ghostty terminal emulator";
  };

  config = lib.mkIf cfg.enable {
    programs.ghostty = {
      # installed via homebrew
      package = null;
      enable = true;
      clearDefaultKeybinds = false;
      enableZshIntegration = true;
      settings = {
        theme = "Gruvbox Dark";
        cursor-style = "block";
        window-padding-x = 5;
        window-padding-y = 5;
        window-padding-balance = true;
        window-colorspace = "display-p3";
        macos-titlebar-style = "hidden";
        quit-after-last-window-closed = true;
        macos-option-as-alt = true;
        auto-update = "off";

        font-family = "JetBrainsMono Nerd Font";
        font-family-bold = "JetBrainsMono Nerd Font";
        font-family-italic = "JetBrainsMono Nerd Font";
        font-family-bold-italic = "JetBrainsMono Nerd Font";

        font-style = "Regular";
        font-style-bold = "Bold";
        font-style-italic = "Italic";
        font-thicken = true;
        font-size = 12;
      };
    };
  };
}
