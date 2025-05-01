{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./touch-id.nix
  ];
  environment = {
    systemPackages = with pkgs; [
      # 1Password has to be installed system-wide
      _1password-cli
    ];
  };
  services = {
    yabai = {
      enable = true;
      config =
        let
          padding = 10;
        in
        {
          layout = "bsp";
          focus_follows_mouse = "off";
          mouse_follows_focus = "off";
          window_placement = "second_child";
          top_padding = padding;
          bottom_padding = padding;
          left_padding = padding;
          right_padding = padding;
          window_gap = padding;
        };
      extraConfig = ''
        yabai -m rule --add app='System Settings' manage=off
        yabai -m config mouse_modifier cmd
      '';
    };
    skhd = {
      enable = true;
      skhdConfig = "
        # Move focus between windows
        alt - h : yabai -m window --focus west
        alt - j : yabai -m window --focus south
        alt - k : yabai -m window --focus north
        alt - l : yabai -m window --focus east

        # Move windows around
        shift + alt - h : yabai -m window --swap west
        shift + alt - j : yabai -m window --swap south
        shift + alt - k : yabai -m window --swap north
        shift + alt - l : yabai -m window --swap east

        shift + alt - r : yabai -m space --rotate 90
      ";
    };
  };

  # Logging is disabled by default
  launchd.user.agents.skhd.serviceConfig = {
    StandardOutPath = "/tmp/skhd.out.log";
    StandardErrorPath = "/tmp/skhd.error.log";
  };

  programs = {
    zsh = {
      enable = true;
      # managed by HM
      enableCompletion = false;
      enableBashCompletion = false;
    };
  };

  networking = {
    hostName = "eve";
    computerName = "Eve";
  };

  fonts = {
    packages = with pkgs.nerd-fonts; [ jetbrains-mono ];
  };

  system = {
    defaults = {
      NSGlobalDomain = {
        AppleFontSmoothing = 2;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        AppleInterfaceStyle = "Dark";
        "com.apple.mouse.tapBehavior" = 1;
      };

      dock = {
        autohide = true;
        autohide-delay = 0.1;
        # autohide-time-modifier = 0.0;
        minimize-to-application = true;
        show-recents = false;
        static-only = true;
      };
      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        ShowPathbar = true;
        CreateDesktop = false;
        QuitMenuItem = true;
      };
      loginwindow = {
        GuestEnabled = false;
        DisableConsoleAccess = true;
      };
      LaunchServices.LSQuarantine = false;
      spaces.spans-displays = false;
    };
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToEscape = true;
    };

    # https://github.com/zhaofengli/nix-homebrew/issues/3#issuecomment-1622240992
    activationScripts = {
      extraUserActivation.text = lib.mkOrder 1501 (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            prefix: d:
            if d.enable then
              ''
                sudo chown -R ${config.nix-homebrew.user} ${prefix}/bin
                sudo chgrp -R ${config.nix-homebrew.group} ${prefix}/bin
              ''
            else
              ""
          ) config.nix-homebrew.prefixes
        )
      );
    };
  };

  security.pam.enableSudoTouchId = true;
}
