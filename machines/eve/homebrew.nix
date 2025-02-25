{config, ...}: {
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
      "ghostty"

      # -- utilities --
      "mullvadvpn"
      "docker"
      "finicky" # choose browser on each link
      "adobe-acrobat-reader"
      "dropbox"
      "google-drive"
      "teamviewer"
      "todoist"
      "yubico-yubikey-manager"
      "trezor-suite"
      "gimp"
      "vlc"
      "balenaetcher"

      # -- 3d printing
      "bambu-studio"
      "orcaslicer"

      # -- communication --
      "telegram"
      "signal"
      "discord"
      "whatsapp"
      "element"

      # -- work --
      "firefox"
      "krisp"
      "postman"
      "slack"
      "microsoft-teams"
      "studio-3t"
      "mongodb-compass"
    ];
    masApps = {
      "1Password for Safari" = 1569813296;
      "Dark Reader for Safari" = 1438243180;
      "WiFi Signal" = 525912054;
      "Xcode" = 497799835;
    };
  };
}
