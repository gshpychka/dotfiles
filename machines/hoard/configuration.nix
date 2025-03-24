{
  config,
  pkgs,
  ...
}: {
  imports = [./hardware-configuration.nix ../../modules/qbittorrent.nix];

  boot = {
    loader = {
      grub.enable = false;
      systemd-boot = {
        enable = true;
        configurationLimit = 3;
      };
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages;
    kernelParams = [
      "scsi_mod.use_blk_mq=1"
      "dm_mod.use_blk_mq=1"
    ];
    kernel.sysctl = {
      "kernel.task_delayacct" = "1"; # Enables task delay accounting at runtime
    };
    tmp = {
      useTmpfs = true;
    };
  };

  networking = {
    hostName = "hoard";
    domain = "lan";
    wireless.enable = false;
    usePredictableInterfaceNames = true;
    enableIPv6 = false;
    interfaces = {
      enp1s0 = {
        wakeOnLan.enable = true;
      };
    };
  };

  time.timeZone = "Europe/Kyiv";

  hardware = {
    gpgSmartcards.enable = true;
    enableAllFirmware = true;
    cpu.intel.updateMicrocode = true;
    usbStorage.manageShutdown = true;
  };

  users = {
    groups.media = {
      members = [
        config.users.users.gshpychka.name
      ];
    };
    users = {
      gshpychka = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = ["wheel" "plugdev" "usb"];
        packages = with pkgs; [neovim git];
        openssh.authorizedKeys.keys = [
          # eve
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG"
        ];
        initialHashedPassword = "";
      };
      "time-machine" = {
        group = config.users.groups.media.name;
        isSystemUser = true;
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
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    samba = {
      enable = true;
      openFirewall = true;
      settings = {
        # https://www.samba.org/samba/docs/current/man-html/vfs_fruit.8.html
        global = {
          "fruit:aapl" = "yes";
          "fruit:nfs_aces" = "no";
        };
        "time-machine" = {
          "vfs objects" = "catia fruit streams_xattr";
          "fruit:time machine" = "yes";
          "fruit: time machine max size" = "2T";
          "fruit:metadata" = "stream";
          "fruit:wipe_intentionally_left_blank_rfork" = "yes";
          "fruit:delete_empty_adfiles" = "yes";
          "fruit:veto_appledouble" = "no";
          "fruit:nfs_aces" = "no";
          "path" = "/mnt/hoard/shares/time-machine";
          "valid users" = "time-machine";
          "public" = "no";
          "writeable" = "yes";
          "force user" = "time-machine";
        };
      };
    };
    nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts = {
        qbittorrent = {
          serverName = "qbittorrent.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.qbittorrent.port}/";
          };
        };
        prowlarr = {
          serverName = "prowlarr.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:9696/";
          };
        };
        sonarr = {
          serverName = "sonarr.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:8989/";
          };
        };
        radarr = {
          serverName = "radarr.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:7878/";
          };
        };
        lidarr = {
          serverName = "lidarr.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:8686/";
          };
        };
        overseerr = {
          serverName = "overseerr.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:5055/";
          };
        };
      };
    };
    glances = {
      # remote system monitoring
      enable = true;
      openFirewall = true;
    };
    fstrim.enable = true;
    plex = {
      enable = true;
      openFirewall = true;
      group = "media";
    };
    qbittorrent = {
      enable = true;
      group = "media";
    };
    prowlarr = {
      enable = true;
    };
    sonarr = {
      enable = true;
      group = "media";
    };
    radarr = {
      enable = true;
      group = "media";
    };
    lidarr = {
      enable = true;
      group = "media";
    };
  };

  systemd = {
    slices."media.slice" = {
      sliceConfig = {
        IOSchedulingClass = "idle";
        IOSchedulingPriority = 3;
        IOWeight = 25;
        # IOReadBandwidthMax = "/mnt/hoard/torrents 20M";
        # IOWriteBandwidthMax = "/mnt/hoard/torrents 10M";
        IOReadIOPSMax = "/mnt/hoard 10";
        IOWriteIOPSMax = "/mnt/hoard 10";
      };
    };
    services = {
      plex.serviceConfig = {
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 0;
        IOWeight = 5000;
      };
      qbittorrent.serviceConfig = {
        # don't want qbittorrent to interfere with Plex
        Slice = "media.slice";
        Nice = 10;
        IOWeight = 50;
        CPUSchedulingPolicy = "idle";
        IOSchedulingPriority = 1;
        IOReadIOPSMax = "/mnt/hoard/torrents 30";
        IOWriteIOPSMax = "/mnt/hoard/torrents 30";
      };
      radarr.serviceConfig = {
        Slice = "media.slice";
      };
      sonarr.serviceConfig = {
        Slice = "media.slice";
      };
      lidarr.serviceConfig = {
        Slice = "media.slice";
      };
    };
  };

  programs = {
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  networking.firewall.allowedTCPPorts = [80];

  system.stateVersion = "24.11";
}
