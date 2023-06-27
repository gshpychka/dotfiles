{ config, pkgs, lib, ... }: {
  homebrew = {
    enable = true;
    onActivation = {
      # "zap" removes manually installed brews and casks
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };
    caskArgs = {
      no_quarantine = true;
    };
    brews = [
      {
        name = "autoraise";
        args = [ "with-dexperimental_focus_first" ];
        restart_service = true;
      }
    ];
    casks = [
      # utilities
      #"browserosaurus" # choose browser on each link
      "hammerspoon"
      "vmware-fusion"
      "balenaetcher"
      "deluge"
      "via"
      "qmk-toolbox"

      # communication
      "telegram"
      "krisp"

      #"beeper"

      "1password"
      "firefox"
      #"visual-studio-code"
      "vlc" # media player
      #"wireshark" # network sniffer
      #"leapp"
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
      "Dimentium/homebrew-autoraise" # AutoRaise
    ];
    masApps = {
      "1Password for Safari" = 1569813296;

    };
  };
}
