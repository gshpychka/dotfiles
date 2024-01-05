{
  config,
  pkgs,
  lib,
  ...
}: {
  homebrew = {
    enable = true;
    onActivation = {
      # "zap" removes manually installed brews and casks
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };
    caskArgs = {no_quarantine = true;};
    casks = [
      # -- essentials --
      "1password"
      "chromium"
      "firefox"
      "raycast"
      "vlc"
      "krisp"

      # -- utilities --
      "finicky" # choose browser on each link
      "vmware-fusion"
      "balenaetcher"
      "adobe-acrobat-reader"
      "dropbox"

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
      "drata-agent"
      "lastpass"
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
