{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [./hardware-configuration.nix];

  boot = {
    loader = {
      grub.enable = false;
      systemd-boot = {
        enable = true;
        configurationLimit = 3;
      };
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  networking = {
    hostName = "reaper";
    domain = "lan";
    wireless.enable = false;
    usePredictableInterfaceNames = true;
    enableIPv6 = false;
    interfaces = {
      eno3 = {
        wakeOnLan.enable = true;
      };
    };
  };

  time.timeZone = "Europe/Kyiv";

  hardware = {
    bluetooth.enable = true;
    gpgSmartcards.enable = true;
    graphics.enable = true;
    enableAllFirmware = true;
    cpu.intel.updateMicrocode = true;
  };

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # ensure GPU is awake while headless
    nvidiaPersistenced = true;

    powerManagement.enable = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = false;

    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  users = {
    users = {
      gshpychka = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = ["wheel" "plugdev" "usb"];
        packages = with pkgs; [neovim git];
        openssh.authorizedKeys.keys = [
          # eve
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG"
          # hass
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ97GzNQODCBpmtUoloIqos0/5ee+CE6CwRMyXIL4MAr"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEFXKhaC9pIMFMeULE7P5pX0GqortRjW9YCKk9EJLRM1"
        ];
        initialHashedPassword = "";
      };
    };
  };

  virtualisation = {
    docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = false;
    enableBashCompletion = false;
  };

  security = {
    sudo.enable = true;
    pam = {
      sshAgentAuth.enable = true;
      services.sudo.sshAgentAuth = true;
    };
  };

  services = {
    pcscd.enable = true;
    udev.packages = [pkgs.yubikey-personalization];
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts = {
        "default" = {
          serverName = config.networking.fqdn;
          locations."/ollama/" = {
            proxyPass = "http://${config.services.ollama.host}:${toString config.services.ollama.port}/";
            recommendedProxySettings = false; # ollama does not work with this on
          };
          locations."/" = {
            return = "404";
          };
        };
      };
    };

    glances = {
      # remote system monitoring
      enable = true;
      openFirewall = true;
    };
    ollama = {
      enable = true;
      user = "ollama";
      acceleration = "cuda";
      openFirewall = false;
      loadModels = [
        "phi3:14b-medium-128k-instruct-q8_0"
        "llama3.1:8b-instruct-fp16" # home assistant
        "llama3.2:3b-instruct-q8_0"
        "gemma2:2b-instruct-q8_0"
        "gemma2:27b-instruct-q6_K"
        "nomic-embed-text:latest"
      ];
    };
    wyoming = {
      faster-whisper = {
        servers.hass = {
          enable = true;
          uri = "tcp://0.0.0.0:10300";
          model = "large-v3";
          language = "en";
          device = "cuda";
        };
      };
      piper = {
        servers.hass = {
          enable = true;
          uri = "tcp://0.0.0.0:10200";
          voice = "en-us-ryan-medium";
        };
      };
    };

    xserver = {
      videoDrivers = ["nvidia"];
    };
    fstrim.enable = true;
  };

  programs = {
    ssh.startAgent = false;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };
  networking.firewall.allowedTCPPorts = [10300 80];

  system.stateVersion = "24.05";
}
