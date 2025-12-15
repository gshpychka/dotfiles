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
