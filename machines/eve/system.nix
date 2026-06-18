{
  pkgs,
  config,
  ...
}:
{
  programs = {
    zsh = {
      enable = true;
      # managed by HM
      enableCompletion = false;
      enableBashCompletion = false;
    };
  };

  fonts = {
    packages = with pkgs.nerd-fonts; [ jetbrains-mono ];
  };

  system = {
    primaryUser = config.my.user;
    defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleFontSmoothing = 2;
        # full keyboard access: Tab reaches lists and panels, not just text fields
        AppleKeyboardUIMode = 2;

        # disable the automatic text substitutions
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;

        # tap to click
        "com.apple.mouse.tapBehavior" = 1;

        # fast key repeat with a short initial delay (lower = faster)
        InitialKeyRepeat = 25;
        KeyRepeat = 2;

        # metric units and Celsius
        AppleMeasurementUnits = "Centimeters";
        AppleMetricUnits = 1;
        AppleTemperatureUnit = "Celsius";
      };

      dock = {
        autohide = true;
        autohide-delay = 0.1;
        # autohide-time-modifier = 0.0;
        minimize-to-application = true;
        show-recents = false;
        static-only = true;
        tilesize = 90;
        # don't reorder Spaces by most-recently-used
        mru-spaces = false;
        # drop the swipe gestures for Launchpad and show-desktop
        showLaunchpadGestureEnabled = false;
        showDesktopGestureEnabled = false;
        # hot corners (action codes, no modifier): bottom-left = Launchpad (11),
        # bottom-right = Mission Control (2)
        wvous-bl-corner = 11;
        wvous-br-corner = 2;
      };

      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        ShowPathbar = true;
        CreateDesktop = false;
        QuitMenuItem = true;
        # new windows open in list view ("Nlsv")
        FXPreferredViewStyle = "Nlsv";
        # purge items from the Trash after 30 days
        FXRemoveOldTrashItems = true;
      };

      WindowManager.HideDesktop = true;

      trackpad = {
        Clicking = true;
        # lightest click pressure (0 light, 1 med, 2 firm)
        FirstClickThreshold = 0;
        SecondClickThreshold = 0;
      };

      screencapture = {
        location = "~/Documents";
        show-thumbnail = false;
      };

      menuExtraClock = {
        IsAnalog = true;
        ShowSeconds = true;
        ShowDayOfWeek = true;
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

  };
  my.sudoTouchId.enable = true;

  # set ulimit for open files to 4096
  # otherwise, `nix flake update` fails with "Too many open files"
  # https://github.com/NixOS/nix/issues/6557
  # https://github.com/NixOS/nix/pull/5726
  launchd.user.agents.ulimit = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        "launchctl limit maxfiles 4096 unlimited"
      ];
      RunAtLoad = true;
    };
  };
}
