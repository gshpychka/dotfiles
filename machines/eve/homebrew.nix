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
      {
        name = "1password";
        greedy = true;
      }
      {
        name = "google-chrome";
        greedy = true;
      }
      {
        name = "raycast";
        greedy = true;
      }
      {
        name = "ghostty";
        greedy = true;
      }

      # -- utilities --
      {
        name = "mullvadvpn";
        greedy = true;
      }
      {
        name = "docker";
        greedy = true;
      }
      {
        name = "finicky";
        greedy = true;
      } # choose browser on each link
      {
        name = "adobe-acrobat-reader";
        greedy = true;
      }
      {
        name = "dropbox";
        greedy = true;
      }
      {
        name = "google-drive";
        greedy = true;
      }
      {
        name = "teamviewer";
        greedy = true;
      }
      {
        name = "yubico-yubikey-manager";
        greedy = true;
      }
      {
        name = "trezor-suite";
        greedy = true;
      }
      {
        name = "gimp";
        greedy = true;
      }
      {
        name = "vlc";
        greedy = true;
      }
      {
        name = "balenaetcher";
        greedy = true;
      }
      {
        name = "chatgpt";
        greedy = true;
      }
      "caldigit-thunderbolt-charging"

      # -- 3d printing
      {
        name = "bambu-studio";
        greedy = true;
      }
      {
        name = "orcaslicer";
        greedy = true;
      }

      # -- communication --
      {
        name = "telegram";
        greedy = true;
      }
      {
        name = "signal";
        greedy = true;
      }
      "discord"
      {
        name = "whatsapp";
        greedy = true;
      }
      {
        name = "element";
        greedy = true;
      }

      # -- work --
      {
        name = "firefox";
        greedy = true;
      }
      {
        name = "postman";
        greedy = true;
      }
      {
        name = "slack";
        greedy = true;
      }
      {
        name = "microsoft-teams";
        greedy = true;
      }
      {
        name = "studio-3t";
        greedy = true;
      }
      {
        name = "mongodb-compass";
        greedy = true;
      }
      {
        name = "lastpass";
        greedy = true;
      }
    ];
    masApps = {
      "1Password for Safari" = 1569813296;
      "Dark Reader for Safari" = 1438243180;
      "WiFi Signal" = 525912054;
      "Xcode" = 497799835;
    };
  };
}
