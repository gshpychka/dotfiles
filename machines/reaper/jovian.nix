{
  config,
  pkgs,
  lib,
  ...
}:
{
  home-manager.users.jovian =
    { ... }:
    {
      home.packages = with pkgs; [ razergenie ];
      programs = {
        firefox.enable = true;
      };
      home.stateVersion = "25.11";
    };

  users = {
    users.jovian = {
      isNormalUser = true;
      extraGroups = [
        "plugdev"
        "usb"
      ]
      ++ lib.optional config.hardware.openrazer.enable "openrazer";
    };
  };

  jovian = {
    steam = {
      enable = true;
      autoStart = true;
      user = config.users.users.jovian.name;
      # Desktop session to switch to from Gaming Mode
      # Using Plasma 6 for a full desktop experience
      desktopSession = "plasma";
    };
    steamos = {
      useSteamOSConfig = false;
      enableZram = true;
      enableSysctlConfig = false;
      enableProductSerialAccess = true;
      enableEarlyOOM = false;
      enableDefaultCmdlineConfig = false;
      enableBluetoothConfig = true;
      enableAutoMountUdevRules = false;
    };
    hardware.has.amd.gpu = false;
  };
  # required at least for the first boot / onboarding
  networking.networkmanager.enable = true;

  services.desktopManager.plasma6.enable = true;

  programs.steam = {
    # will need to enable GUI hardware acceleration once in desktop mode
    # otherwise, UI will be laggy
    # that's the only reason to enable Steam here
    enable = true;
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

  # required for PipeWire
  security.rtkit.enable = true;
}
