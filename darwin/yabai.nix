{ config, pkgs, lib, ... }: {
  services.yabai = {
    enable = false;
    # package = "pkgs.yabai";
    enableScriptingAddition = true;
    config = {
      layout = "managed";
    };
  };

  services.skhd = {
    enable = true;
    skhdConfig = let yabai = "${pkgs.yabai}/bin/yabai"; in
      ''
        # alt + a / u / o / s are blocked due to umlaute

        # workspaces
        ctrl + alt - j : ${yabai} -m space --focus prev
        ctrl + alt - k : ${yabai} -m space --focus next
        cmd + alt - j : ${yabai} -m space --focus prev
        cmd + alt - k : ${yabai} -m space --focus next

        # send window to space and follow focus
        ctrl + alt - l : ${yabai} -m window --space prev; ${yabai} -m space --focus prev
        ctrl + alt - h : ${yabai} -m window --space next; ${yabai} -m space --focus next
        cmd + alt - l : ${yabai} -m window --space prev; ${yabai} -m space --focus prev
        cmd + alt - h : ${yabai} -m window --space next; ${yabai} -m space --focus next

        # focus window
        alt - h : ${yabai} -m window --focus west
        alt - l : ${yabai} -m window --focus east

        # focus window in stacked
        alt - j : if [ "$(${yabai} -m query --spaces --space | jq -r '.type')" = "stack" ]; then ${yabai} -m window --focus stack.next; else ${yabai} -m window --focus south; fi
        alt - k : if [ "$(${yabai} -m query --spaces --space | jq -r '.type')" = "stack" ]; then ${yabai} -m window --focus stack.prev; else ${yabai} -m window --focus north; fi

        # swap managed window
        shift + alt - h : ${yabai} -m window --swap west
        shift + alt - j : ${yabai} -m window --swap south
        shift + alt - k : ${yabai} -m window --swap north
        shift + alt - l : ${yabai} -m window --swap east

        # increase window size
        shift + alt - a : ${yabai} -m window --resize left:-20:0
        shift + alt - s : ${yabai} -m window --resize right:-20:0

        # toggle layout
        alt - t : ${yabai} -m space --layout bsp
        alt - d : ${yabai} -m space --layout stack

        # float / unfloat window and center on screen
        alt - n : ${yabai} -m window --toggle float; \
                  ${yabai} -m window --grid 4:4:1:1:2:2

        # toggle sticky(+float), topmost, picture-in-picture
        alt - p : ${yabai} -m window --toggle sticky; \
                  ${yabai} -m window --toggle topmost; \
                  ${yabai} -m window --toggle pip

        # reload
        # shift + alt - r : brew services restart skhd; brew services restart yabai; brew services restart sketchybar
      '';
  };
}
