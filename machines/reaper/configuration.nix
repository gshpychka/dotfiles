{
  config,
  pkgs,
  ...
}:
{
  imports = [ ./hardware-configuration.nix ];

  boot = {
    loader = {
      grub.enable = false;
      systemd-boot = {
        enable = true;
        configurationLimit = 2;
      };
      efi.canTouchEfiVariables = true;
      timeout = 3;
    };
    kernelPackages = pkgs.linuxPackages_latest;
    plymouth = {
      enable = true;
    };
    kernelParams = [
      "quiet"
      "splash"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    initrd.verbose = false;
    tmp = {
      useTmpfs = true;
      tmpfsSize = "32G";
    };
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

  users = {
    defaultUserShell = pkgs.zsh;
    users = {
      gshpychka = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "plugdev"
          "usb"
        ];
        openssh.authorizedKeys.keys = [
          # eve
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG"
        ];
        linger = true;
        initialHashedPassword = "";
      };
      hass = {
        group = "homeassistant";
        isSystemUser = true;
        useDefaultShell = true;
        openssh.authorizedKeys.keys = [
          # homeassistant.local
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAC9nquQBUuHWrWJvuUJLuR2zfupJp+QtQlpck0n5J0J"
        ];
      };
    };
    groups.homeassistant = { };
  };

  security = {
    pam = {
      sshAgentAuth.enable = true;
      services.sudo.sshAgentAuth = true;
    };
    sudo = {
      enable = true;
      extraRules = [
        {
          users = [ "hass" ];
          commands = [
            {
              command = "${pkgs.systemd}/bin/bootctl";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/reboot";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/shutdown";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };
  };

  hardware = {
    bluetooth.enable = true;
    gpgSmartcards.enable = true;
    enableAllFirmware = true;
    cpu.intel.updateMicrocode = true;
    nvidia = {
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
    nvidia-container-toolkit.enable = true;
    graphics = {
      enable = true;
    };
  };

  virtualisation = {
    docker = {
      enable = true;
      storageDriver = "overlay2";
      rootless = {
        enable = true;
        setSocketVariable = true;
        daemon.settings = {
          max-concurrent-downloads = 10;
          features.cdi = true;
        };
      };
      autoPrune.enable = true;
    };
    oci-containers = {
      backend = "docker";
      containers = {
        kokoro-fastapi = {
          image = "ghcr.io/remsky/kokoro-fastapi-gpu:v0.2.2";
          ports = [ "8000:8880" ];
          extraOptions = [
            "--device"
            "nvidia.com/gpu=all"
          ];
        };
      };
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = false;
    enableBashCompletion = false;
  };

  services = {
    pcscd.enable = true;
    udev.packages = [ pkgs.yubikey-personalization ];
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
      recommendedProxySettings = false; # ollama does not work with this on
      virtualHosts = {
        "default" = {
          serverName = config.networking.fqdn;
          locations = {
            "/ollama/" = {
              proxyPass = "http://${config.services.ollama.host}:${toString config.services.ollama.port}/";
            };
            "/kokoro/" = {
              proxyPass = "http://127.0.0.1:8000/";
              recommendedProxySettings = true;
            };
            "/" = {
              return = "404";
            };
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
      acceleration = "cuda";
      openFirewall = false;
      loadModels = [
        "llama3.1:8b-instruct-fp16"
        "qwen2.5:14b-instruct-q8_0" # home assistant
        "qwen3:14b-q8_0"
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
    };

    xserver = {
      videoDrivers = [ "nvidia" ];
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
  networking.firewall.allowedTCPPorts = [
    10300
    80
  ];

  system.stateVersion = "24.05";
}
