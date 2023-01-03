{ config, pkgs, lib, ... }: {
  homebrew = {
    enable = true;
    onActivation = {
      # "zap" removes manually installed brews and casks
      cleanup = "zap";
      autoUpdate = true;
    };
    brews = [
      #"skhd" # keybinding manager
      #"yabai" # tiling window manager
    ];
    casks = [
      # utilities
      #"bartender" # hides mac bar icons
      #"browserosaurus" # choose browser on each link
      #"karabiner-elements" # remap keyboard
      #"macfuse" # file system utilities

      # virtualization
      "docker" # docker desktop

      # communication
      #"mutify" # one click mute button
      "zoom"
      "slack"
      "discord"
      "telegram"

      "1password"

      "firefox"
      "postman"
      #"shottr" # screenshot tool
      #"the-unarchiver"
      "visual-studio-code"
      #"vlc" # media player
      #"eul" # mac monitoring
      #"kindavim" # vim keys for everything
      #"kap" # screen recorder software
      #"wireshark" # network sniffer
      #"sf-symbols" # patched font for sketchybar
    ];
    taps = [
      # default
      "homebrew/bundle"
      "homebrew/cask"
      "homebrew/cask-drivers"
      "homebrew/cask-fonts"
      "homebrew/core"
      "homebrew/services"
      # custom
      "cmacrae/formulae" # spacebar
      "koekeishiya/formulae" # yabai
      "FelixKratz/formulae" # sketchybar
    ];
    masApps = {
      "1Password for Safari" = 1569813296;

    };
  };
}
