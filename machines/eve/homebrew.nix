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
      "via"
      "qmk-toolbox"
      "adobe-acrobat-reader"

      # -- communication --
      "telegram"
      "krisp"
      #"beeper"

      # -- work --
      # "drata-agent"
      "lastpass"
      "leapp"
      "slack"
      "docker"

      "1password"
      "firefox"
      "vlc" # media player
    ];
    masApps = {
      "1Password for Safari" = 1569813296;
    };
  };
}
