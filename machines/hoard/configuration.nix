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
    kernelPackages = pkgs.linuxPackages_latest;
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
  };

  users = {
    groups.media = {
      members = [
        config.users.users.gshpychka.name
        config.services.plex.user
        config.services.qbittorrent.user
        config.services.sonarr.user
        config.services.radarr.user
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
        default = {
          serverName = config.networking.fqdn;
          locations."/qbittorrent/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.qbittorrent.port}/";
          };
          locations."/prowlarr/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.prowlarr.port}/";
          };
          locations."/sonarr/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.sonarr.port}/";
          };
          locations."/radarr/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.radarr.port}/";
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
    fstrim.enable = true;
    plex = {
      enable = true;
    };
    qbittorrent = {
      enable = true;
    };
    prowlarr = {
      enable = true;
    };
    sonarr = {
      enable = true;
    };
    radarr = {
      enable = true;
    };
  };

  programs = {
    ssh.startAgent = false;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  system.stateVersion = "24.11";
}
