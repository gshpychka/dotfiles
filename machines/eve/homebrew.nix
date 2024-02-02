{
  config,
  pkgs,
  lib,
  ...
}: {
  homebrew = {
    enable = true;
    taps = builtins.attrNames config.nix-homebrew.taps;
    global = {
      # nix-homebrew is handling homebrew updates
      autoUpdate = false;
    };
    onActivation = {
      # "zap" removes manually installed brews and casks
      cleanup = "zap";
      # nix-homebrew is handling homebrew updates
      autoUpdate = false;
      upgrade = true;
    };
    caskArgs = {no_quarantine = true;};
    casks = [
      # -- essentials --
      "1password"
      "google-chrome"
      "raycast"
      "vlc"

      # -- utilities --
      "finicky" # choose browser on each link
      "vmware-fusion"
      "balenaetcher"
      "adobe-acrobat-reader"
      "dropbox"
      "google-drive"

      # -- 3d printing
      "bambu-studio"
      "orcaslicer"

      # -- communication --
      "telegram"
      "signal"
      "discord"
      "whatsapp"
      #"beeper"

      # -- work --
      "firefox"
      "krisp"
      "leapp"
      "slack"
      "docker"
      "visual-studio-code"
    ];
    masApps = {
      "1Password for Safari" = 1569813296;
      "Dark Reader for Safari" = 1438243180;
      "WiFi Signal" = 525912054;
      "Xcode" = 497799835;
    };
  };
}
