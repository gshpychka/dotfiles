{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./touch-id.nix
  ];
  environment = {
    systemPackages = with pkgs; [
      _1password
    ];
  };
  services = {
    nix-daemon.enable = true;
    yabai = {
      enable = true;
      config = let
        padding = 10;
      in {
        layout = "bsp";
        focus_follows_mouse = "autofocus";
        mouse_follows_focus = "off";
        window_placement = "second_child";
        top_padding = padding;
        bottom_padding = padding;
        left_padding = padding;
        right_padding = padding;
        window_gap = padding;
      };
      extraConfig = "
        yabai -m rule --add app='System Settings' manage=off
        yabai -m rule --add app='krisp' manage=off
        yabai -m rule --add app='Leapp' manage=off
        # Make non-resizable windows floating
        yabai -m signal --add event=window_created action='yabai -m query --windows --window $YABAI_WINDOW_ID | jq -er \".\\\"can-resize\\\" and .\\\"is-floating\\\"\" || yabai -m window $YABAI_WINDOW_ID --toggle float'
      ";
    };
    skhd = {
      enable = true;
      skhdConfig = "
        # Move focus between windows
        ctrl + alt - h : yabai -m window --focus west
        ctrl + alt - j : yabai -m window --focus south
        ctrl + alt - k : yabai -m window --focus north
        ctrl + alt - l : yabai -m window --focus east

        # Move windows around
        shift + alt - h : yabai -m window --swap west
        shift + alt - j : yabai -m window --swap south
        shift + alt - k : yabai -m window --swap north
        shift + alt - l : yabai -m window --swap east

        shift + alt + r : yabai -m space --rotate 90
      ";
    };
  };

  programs = {
    zsh = {
      enable = true;
      enableCompletion = false;
      enableBashCompletion = false;
    };
  };

  networking = {
    hostName = "eve";
    computerName = "Eve";
  };

  fonts = {
    fontDir.enable = true;
    fonts = with pkgs; [(nerdfonts.override {fonts = ["JetBrainsMono"];})];
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

      # CustomUserPreferences = {
      #   # TODO: link all hammerspoon stuff together
      #   "org.hammerspoon.Hammerspoon".MJConfigFile = "~/.config/hammerspoon.lua";
      # };
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
    # build.applications = pkgs.lib.mkForce (pkgs.buildEnv {
    #   name = "applications";
    #   # link home-manager apps into /Applications instead of ~/Applications
    #   # fix from https://github.com/LnL7/nix-darwin/issues/139#issuecomment-663117229
    #   paths = config.environment.systemPackages ++ config.home-manager.users.${config.user}.home.packages;
    #   pathsToLink = "/Applications";
    # });

    # https://github.com/zhaofengli/nix-homebrew/issues/3#issuecomment-1622240992
    activationScripts = {
      extraUserActivation.text = lib.mkOrder 1501 (lib.concatStringsSep "\n" (lib.mapAttrsToList (prefix: d:
        if d.enable
        then ''
          sudo chown -R ${config.nix-homebrew.user} ${prefix}/bin
          sudo chgrp -R ${config.nix-homebrew.group} ${prefix}/bin
        ''
        else "")
      config.nix-homebrew.prefixes));
    };
  };

  security.pam.enableSudoTouchId = true;
}
