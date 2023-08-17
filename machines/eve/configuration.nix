{
  config,
  pkgs,
  lib,
  ...
}: {
  environment = {
    systemPackages = with pkgs; [
      # nodePackages."@githubnext/github-copilot-cli"
      yubikey-manager
      zstd
      # element-desktop
      # zoom-us
      # slack
      discord
      _1password
      # _1password-gui-beta
    ];
  };

  services = {
    nix-daemon.enable = true;
    yabai = {
      enable = true;
      config = let padding = 10; in {
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
    #   # TODO: parametrize the username
    #   paths = config.environment.systemPackages ++ config.home-manager.users.gshpychka.home.packages;
    #   pathsToLink = "/Applications";
    # });
  };

  # using https://github.com/jnooree/pam-watchid as well
  # because pam_tid.so (below) does not prompt for Watch auth with lid closed
  security.pam.enableSudoTouchIdAuth = true;
}
