{
  pkgs,
  config,
  ...
}:
{
  imports = [
    ./boot.nix
    ./nix.nix
    ./filesystems.nix
    ./hardware.nix
    ./kokoro.nix
    ./whisper.nix
    ./monitoring.nix
    ./home.nix
    # ./openwebui.nix
    # ./comfyui.nix
  ];
  networking.hostName = "reaper";
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "24.05";

  networking = {
    usePredictableInterfaceNames = true;
    enableIPv6 = false;
    useDHCP = true;
    interfaces = {
      eno3 = {
        wakeOnLan.enable = true;
      };
    };
  };
  my.tailscale = {
    enable = true;
    ssh = true;
  };

  my.buildServer = {
    enable = true;
    systems = [
      # Support both native and ARM builds
      "x86_64-linux"
      "aarch64-linux"
    ];
    maxJobs = 16;
    speedFactor = 100;
    supportedFeatures = [
      "nixos-test"
      "benchmark"
      "big-parallel"
      "kvm"
    ];
    clientPublicKeys = [
      config.my.nixbuildKeys.eve
      config.my.nixbuildKeys.hoard
      config.my.nixbuildKeys.harbor
    ];
  };

  # Enable QEMU binfmt emulation for cross-compilation
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

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
          config.my.sshKeys.main
        ];
        linger = true;
        initialHashedPassword = "";
      };
      hass = {
        group = "homeassistant";
        isSystemUser = true;
        useDefaultShell = true;
        openssh.authorizedKeys.keys = [
          config.my.sshKeys.homeassistant
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
              command = "/run/current-system/sw/bin/bootctl";
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
        # name = "qwen3:14b-q8_0";
        name = "qwen3:14b-q4_K_M";
        loadIntoVram = true;
      }
      {
        name = "llama3.1:8b-instruct-fp16";
      }
    ];
  };

  my.terminfo.enable = true;

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
      recommendedTlsSettings = true;
      virtualHosts = {
        "default" = {
          serverName = config.networking.fqdn;
          useACMEHost = config.networking.fqdn;
          onlySSL = true;
          default = true;
          locations = {
            "/" = {
              return = "404";
            };
          };
        };
      };
    };

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
  ];

}
