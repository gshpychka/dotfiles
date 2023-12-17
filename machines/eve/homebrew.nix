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
      # -- utilities --
      "finicky" # choose browser on each link
      "vmware-fusion"
      "balenaetcher"
      "transmission"
      "adobe-acrobat-reader"
      "dropbox"

      # -- 3d printing
      "bambu-studio"
      "orcaslicer"

      # -- communication --
      "telegram"
      "krisp"
      #"beeper"

      # -- work --
      "drata-agent"
      "lastpass"
      "leapp"
      "slack"
      "docker"
      "visual-studio-code"

      "1password"
      "firefox"
      "google-chrome"
      "vlc"
    ];
    masApps = {
      "1Password for Safari" = 1569813296;
    };
  };
}
