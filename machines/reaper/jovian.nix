{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Jovian NixOS gaming configuration for desktop with NVIDIA GPU
  # Note: Jovian is primarily designed for AMD GPUs (Steam Deck), so NVIDIA support
  # may have quirks. Do NOT enable mesa-git or AMD-specific options.

  jovian = {
    steam = {
      enable = true;
      # Auto-start Steam Deck UI on boot (Gaming Mode)
      autoStart = true;
      # User to run Steam as
      user = config.my.user;
      # Desktop session to switch to from Gaming Mode
      # Using Plasma 6 for a full desktop experience
      desktopSession = "plasma";
    };

    # Do NOT enable AMD GPU option - we have NVIDIA
    # jovian.hardware.has.amd.gpu = false; # (this is the default)

    # Enable SteamOS-style system configuration
    # - USB storage automounting
    # - Bluetooth optimizations for controllers
    # - earlyoom memory management
    # - sysctl kernel tuning
    steamos.useSteamOSConfig = true;
  };

  # Enable Plasma 6 as the desktop environment for "Switch to Desktop" functionality
  services.desktopManager.plasma6.enable = true;

  # Enable Steam with Proton support for running Windows games
  programs.steam = {
    enable = true;
    # Enable GameScope compositor for better gaming performance
    gamescopeSession.enable = true;
    # Remote play support
    remotePlay.openFirewall = true;
    # Dedicated server support
    dedicatedServer.openFirewall = true;
    # Local network game transfers
    localNetworkGameTransfers.openFirewall = true;
  };

  # Enable GameMode for on-demand performance optimizations
  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        renice = 10;
      };
      gpu = {
        # NVIDIA-specific: don't try to set AMD performance levels
        apply_gpu_optimisations = "accept-responsibility";
        # NVIDIA performance mode via nvidia-settings
        gpu_device = 0;
        nv_powermizer_mode = 1; # Prefer maximum performance
      };
    };
  };

  # 32-bit graphics support for Steam/Proton games
  hardware.graphics.enable32Bit = true;

  # Audio setup - PipeWire with low latency for gaming
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    # Low latency configuration for gaming
    extraConfig.pipewire = {
      "99-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 64;
          "default.clock.min-quantum" = 32;
          "default.clock.max-quantum" = 1024;
        };
      };
    };
  };

  # Required for PipeWire
  security.rtkit.enable = true;

  # Gaming-related packages
  environment.systemPackages = with pkgs; [
    # Game launchers
    lutris
    heroic # Epic Games / GOG launcher

    # Wine/Proton utilities
    winetricks
    protontricks

    # Gaming utilities
    mangohud # Performance overlay
    goverlay # MangoHud configuration GUI

    # Controller support
    game-devices-udev-rules

    # NVIDIA tools
    nvtopPackages.full
  ];

  # Controller udev rules
  services.udev.packages = with pkgs; [
    game-devices-udev-rules
  ];

  # Open firewall for common gaming ports
  networking.firewall = {
    # Steam streaming, remote play
    allowedTCPPorts = [
      27036
      27037
    ];
    allowedUDPPorts = [
      27031
      27036
    ];
  };
}
