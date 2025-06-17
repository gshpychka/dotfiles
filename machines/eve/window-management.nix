{ ... }:
{
  services = {
    yabai = {
      enable = true;
      config =
        let
          padding = 10;
        in
        {
          layout = "bsp";
          focus_follows_mouse = "off";
          mouse_follows_focus = "off";
          window_placement = "second_child";
          top_padding = padding;
          bottom_padding = padding;
          left_padding = padding;
          right_padding = padding;
          window_gap = padding;
        };
      extraConfig = ''
        yabai -m rule --add app='System Settings' manage=off
        yabai -m config mouse_modifier cmd
      '';
    };
    skhd = {
      enable = true;
      skhdConfig = "
        # Move focus between windows
        alt - h : yabai -m window --focus west
        alt - j : yabai -m window --focus south
        alt - k : yabai -m window --focus north
        alt - l : yabai -m window --focus east

        # Move windows around
        shift + alt - h : yabai -m window --swap west
        shift + alt - j : yabai -m window --swap south
        shift + alt - k : yabai -m window --swap north
        shift + alt - l : yabai -m window --swap east

        shift + alt - r : yabai -m space --rotate 90
      ";
    };
  };

  # Logging is disabled by default
  launchd.user.agents.skhd.serviceConfig = {
    StandardOutPath = "/tmp/skhd.out.log";
    StandardErrorPath = "/tmp/skhd.error.log";
  };
}
