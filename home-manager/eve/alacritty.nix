{...}: {
  programs.alacritty = {
    enable = true;
    settings = {
      env.TERM = "alacritty";
      window = {
        opacity = 1;
        dynamic_title = true;
        dynamic_padding = true;
        decorations = "buttonless";
        dimensions = {
          lines = 0;
          columns = 0;
        };
        padding = {
          x = 5;
          y = 5;
        };
        option_as_alt = "OnlyLeft";
      };

      scrolling = {
        history = 10000;
        multiplier = 3;
      };

      mouse = {hide_when_typing = false;};

      keyboard.bindings = [];

      font = let
        fontname = "JetBrainsMono Nerd Font";
      in {
        normal = {
          family = fontname;
          style = "Regular";
        };
        bold = {
          family = fontname;
          style = "Bold";
        };
        italic = {
          family = fontname;
          style = "Italic";
        };
        size = 12;
      };
      cursor.style = "Block";

      colors = {
        primary = {
          background = "#282828";
          foreground = "#fbf1c7";
          bright_foreground = "#f9f5d7";
          dim_foreground = "#f2e5bc";
        };
        cursor = {
          text = "CellBackground";
          cursor = "CellForeground";
        };
        vi_mode_cursor = {
          text = "CellBackground";
          cursor = "CellForeground";
        };
        selection = {
          text = "CellBackground";
          background = "CellForeground";
        };
        normal = {
          black = "#282828";
          red = "#cc241d";
          green = "#98971a";
          yellow = "#d79921";
          blue = "#458588";
          magenta = "#b16286";
          cyan = "#689d6a";
          white = "#a89984";
        };
        bright = {
          black = "#928374";
          red = "#fb4934";
          green = "#b8bb26";
          yellow = "#fabd2f";
          blue = "#83a598";
          magenta = "#d3869b";
          cyan = "#8ec07c";
          white = "#ebdbb2";
        };
      };
    };
  };
}
