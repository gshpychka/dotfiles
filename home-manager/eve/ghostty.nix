{...}: {
  programs.ghostty = {
    enable = true;
    clearDefaultKeybinds = true;
    enableZshIntegration = true;
    settings = {
      theme = "GruvboxDark";
      cursor_style = "block";
      window_padding_x = 5;
      window_padding_y = 5;
      window_padding_balance = true;
      window_colorspace = "display-p3";
      macos_titlebar_style = "hidden";
      quit_after_last_window_closed = true;
      macos_option_as_alt = true;
      auto_update = "off";

      font_family = "JetBrainsMono Nerd Font";
      font-family-bold = "JetBrainsMono Nerd Font";
      font-family-italic = "JetBrainsMono Nerd Font";
      font-family-bold-italic = "JetBrainsMono Nerd Font";

      font_style = "Regular";
      font_style_bold = "Bold";
      font_style_italic = "Italic";
      font_thicken = true;
      font_size = 12;
    };
  };
}
