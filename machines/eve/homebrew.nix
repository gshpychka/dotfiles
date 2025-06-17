{
  config,
  lib,
  inputs,
  ...
}:
{
  nix-homebrew = {
    enable = true;
    enableRosetta = false;
    user = config.system.primaryUser;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };
    mutableTaps = false;
    extraEnv = {
      HOMEBREW_NO_ANALYTICS = "1";
    };
  };
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
    caskArgs = {
      no_quarantine = true;
    };
    casks = [
      # -- essentials --
      "google-chrome"
      "raycast"
      {
        name = "ghostty";
        greedy = true;
      }
      # -- utilities --
      {
        name = "mullvad-vpn";
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
        name = "betterdisplay";
      }
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
        name = "cyberduck";
        greedy = true;
      }
      {
        name = "teamviewer";
        greedy = true;
      }
      {
        name = "yubico-authenticator";
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
      {
        name = "plexamp";
        greedy = true;
      }
      {
        name = "dash";
        greedy = true;
      }
      "tailscale"
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
      "telegram"
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
      "zoom"

      # -- work --
      {
        name = "firefox";
        greedy = true;
      }
      "postman"
      {
        name = "slack";
        greedy = true;
      }
      {
        name = "microsoft-teams";
        greedy = true;
      }
      {
        name = "mongodb-compass";
        greedy = true;
      }
    ];
    masApps = {
      "Dark Reader for Safari" = 1438243180;
      "WiFi Signal" = 525912054;
      "Xcode" = 497799835;
    };
  };
  # https://github.com/zhaofengli/nix-homebrew/issues/3#issuecomment-1622240992
  system.activationScripts.fixHomebrewPermissions.text = lib.mkOrder 1501 (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        prefix: d:
        if d.enable then
          ''
            chown -R ${config.nix-homebrew.user} ${prefix}/bin
            chgrp -R ${config.nix-homebrew.group} ${prefix}/bin
          ''
        else
          ""
      ) config.nix-homebrew.prefixes
    )
  );

}
