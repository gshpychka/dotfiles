{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/acme.nix
    ../../modules/ollama.nix
  ];

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
    # https://forums.developer.nvidia.com/t/6-15-kernel-and-closed-module-compatibility-in-570-153-02/333711
    kernelPackages = pkgs.linuxPackages_6_14;
    plymouth = {
      enable = true;
    };
    kernelParams = [
      "quiet"
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
    wireless.enable = false;
    usePredictableInterfaceNames = true;
    enableIPv6 = false;
    interfaces = {
      eno3 = {
        wakeOnLan.enable = true;
      };
    };
  };

  users = {
    defaultUserShell = pkgs.zsh;
    users = {
      ${config.my.user} = {
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
  nixpkgs.config = {
    # We shouldn't set cudaSupport = true here, because it will lead to
    # building e.g. pytorch from source
    # Omitting it does NOT prevent CUDA support
    # If a package requires this flag, use an override

    # Keeping this here to be explicit
    # cudaSupport = true;

    # https://en.wikipedia.org/wiki/CUDA#GPUs_supported
    cudaCapabilities = [ "8.9" ];
    cudaForwardCompat = true;
    nvidia.acceptLicense = true;
  };
  nixpkgs.overlays = [
    # Since we don't set cudaSupport = true globally, we need to enable CUDA
    # for each package that requires it
    (self: super: {
      ctranslate2 = super.ctranslate2.override {
        withCUDA = true;
        withCuDNN = true;
      };
      btop = super.btop.override { cudaSupport = true; };
    })
  ];

  nix.settings = {
    allowed-users = [ config.my.user ];
    trusted-users = [ config.my.user ];

    auto-optimise-store = true;
    accept-flake-config = true;
    http-connections = 0;
    download-buffer-size = 500000000;
    extra-substituters = [ "https://cuda-maintainers.cachix.org" ];
    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };
  nix.gc = {
    dates = "weekly";
    automatic = true;
    options = "--delete-older-than 7d";
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

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  my.acme = {
    enable = true;
    domain = config.my.domain;
    extraDomainNames = [ "*.${config.networking.fqdn}" ];
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
    enableLsColors = false;
  };

  my.ollama = {
    enable = true;
    loadModels = [
      {
        # home assistant
        name = "qwen2.5:14b-instruct-q8_0";
        loadIntoVram = true;
      }
      {
        name = "llama3.1:8b-instruct-fp16";
      }
      {
        name = "qwen3:14b-q8_0";
      }
    ];
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
      streamConfig = ''
        upstream wyoming_whisper {
          server 127.0.0.1:10300;
        }

        server {
          listen 10299;
          proxy_pass           wyoming_whisper;
          proxy_socket_keepalive on;
        }
      '';
      recommendedTlsSettings = true;
      virtualHosts = {
        "default" = {
          serverName = config.networking.fqdn;
          useACMEHost = config.networking.fqdn;
          onlySSL = true;
          default = true;
          locations = {
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
    wyoming = {
      faster-whisper = {
        servers.hass = {
          enable = true;
          uri = "tcp://127.0.0.1:10300";
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
    config.services.nginx.defaultSSLListenPort
    10299 # faster-whisper
  ];

  system.stateVersion = "24.05";
}
