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
        name = "docker-desktop";
        greedy = true;
      }
      {
        # choose browser on each link
        name = "finicky";
        greedy = true;
      }
      {
        name = "betterdisplay";
      }
      {
        name = "insta360-link-controller";
      }
      {
        name = "dropbox";
        greedy = true;
      }
      {
        name = "google-drive";
        greedy = false;
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
        name = "tailscale-app";
        greedy = true;
      }
      "coconutbattery"
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
        greedy = false;
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
        greedy = false;
      }
      {
        name = "mongodb-compass";
        greedy = true;
      }
      "microsoft-excel"
    ];
    brews = [
      "mas"
    ];
    masApps = {
      "Dark Reader for Safari" = 1438243180;
      "WiFi Signal" = 525912054;
      "Xcode" = 497799835;
      "Flow - Focus & Pomodoro Timer" = 1423210932;
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
