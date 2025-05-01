{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/qbittorrent.nix
    ../../modules/sabnzbd.nix
  ];
  disabledModules = [ "services/networking/sabnzbd.nix" ];
  nixpkgs.overlays = [ (import ../../overlays/nzbget.nix) ];

  boot = {
    loader = {
      grub.enable = false;
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
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
      "vm.dirty_background_bytes" = "268435456"; # 256 MB
      "vm.dirty_bytes" = "805306368"; # 768 MB

      # Spread out flushing more evenly over time
      "vm.dirty_writeback_centisecs" = "100"; # 1 second interval
      "vm.dirty_expire_centisecs" = "3000"; # 30s max cache age
    };
    tmp = {
      useTmpfs = true;
    };
  };
  environment.systemPackages = with pkgs; [
    cryptsetup
  ];

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

  sops = {
    defaultSopsFile = ../../secrets/hoard/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      radarr-api-key = { };
      sonarr-api-key = { };
      lidarr-api-key = { };
      prowlarr-api-key = { };
      qbittorrent-username = { };
      qbittorrent-password = { };
      nzbget-username = { };
      nzbget-password = { };
      plex-token = { };
    };
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
        extraGroups = [
          "wheel"
          "plugdev"
          "usb"
        ];
        packages = with pkgs; [
          neovim
          git
          sysstat
          iotop
          unrar
        ];
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
        nzbget = {
          serverName = "nzbget.${config.networking.fqdn}";
          locations."/" = {
            # TODO: reference port from module
            proxyPass = "http://127.0.0.1:6789/";
          };
        };
        homepage = {
          serverName = "home.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.homepage-dashboard.listenPort}/";
          };
        };
      };
    };
    homepage-dashboard = {
      enable = true;
      title = "hoard";
      widgets = [
        {
          glances = {
            url = "http://127.0.0.1:${toString config.services.glances.port}";
            username = config.sops.secrets.glances-username.path;
            password = config.sops.secrets.glances-password.path;
            version = 4;
            cputemp = true;
            uptime = true;
            disk = [
              "/mnt/hoard"
              "/"
            ];
          };
        }
      ];
      services = [
        {
          "Streaming" = [
            {
              "Plex" = {
                icon = "plex.png";
                href = "https://app.plex.tv";
                widgets = [
                  {
                    type = "plex";
                    url = "http://127.0.0.1:32400";
                    key = config.sops.secrets.plex-token.path;
                  }
                ];
              };
            }
          ];
        }
        {
          "Downloaders" = [
            {
              "qBittorrent" = {
                icon = "qbittorrent.png";
                href = "http://qbittorrent.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "qbittorrent";
                    url = "http://127.0.0.1:${toString config.services.qbittorrent.port}";
                    username = config.sops.secrets.qbittorrent-username.path;
                    password = config.sops.secrets.qbittorrent-password.path;
                  }
                ];
              };
            }
            {
              "nzbget" = {
                icon = "nzbget.png";
                href = "http://nzbget.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "nzbget";
                    url = "http://127.0.0.1:6789";
                    username = config.sops.secrets.nzbget-username.path;
                    password = config.sops.secrets.nzbget-password.path;
                  }
                ];
              };
            }
          ];
        }
        {
          "Arr stack" = [
            {
              "Sonarr" = {
                icon = "sonarr.png";
                href = "http://sonarr.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "sonarr";
                    url = "http://127.0.0.1:8989";
                    key = config.sops.secrets.sonarr-api-key.path;
                  }
                ];
              };
            }
            {
              "Radarr" = {
                icon = "radarr.png";
                href = "http://radarr.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "radarr";
                    url = "http://127.0.0.1:7878";
                    key = config.sops.secrets.radarr-api-key.path;
                  }
                ];
              };
            }
            {
              "Lidarr" = {
                icon = "lidarr.png";
                href = "http://lidarr.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "lidarr";
                    url = "http://127.0.0.1:8686";
                    key = config.sops.secrets.lidarr-api-key.path;
                  }
                ];
              };
            }
            {
              "Sonarr" = {
                icon = "sonarr.png";
                href = "http://sonarr.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "sonarr";
                    url = "http://127.0.0.1:8989";
                    key = config.sops.secrets.sonarr-api-key.path;
                  }
                ];
              };
            }
            {
              "Prowlarr" = {
                icon = "prowlarr.png";
                href = "http://prowlarr.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "prowlarr";
                    url = "http://127.0.0.1:9696";
                    key = config.sops.secrets.prowlarr-api-key.path;
                  }
                ];
              };
            }
          ];
        }
      ];
    };

    glances = {
      # remote system monitoring
      enable = true;
      openFirewall = true;
      extraArgs = [
        "--username"
        config.sops.secrets.glances-username.path
        "--password"
        config.sops.secrets.glances-password.path
      ];
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
    nzbget = {
      enable = true;
      package = pkgs.nzbget;
      group = "media";
    };
    recyclarr = {
      enable = true;
      group = "media";
      configuration = {
        radarr.radarr = {
          api_key._secret = "/run/credentials/recyclarr.service/radarr-api-key";
          base_url = "http://localhost:7878";
        };
        sonarr.sonarr = {
          api_key._secret = "/run/credentials/recyclarr.service/sonarr-api-key";
          base_url = "http://localhost:8989";
          delete_old_custom_formats = true;
          replace_existing_custom_formats = true;
          quality_profiles = [
            {
              name = "Any";
              min_format_score = 0;
              upgrade = {
                allowed = true;
                until_quality = "Bluray-2160p Remux";
                until_score = 10000;
              };
            }
          ];
          custom_formats = [
            {
              trash_ids = [
                "2b239ed870daba8126a53bd5dc8dc1c8" # DV HDR10+
                "7878c33f1963fefb3d6c8657d46c2f0a" # DV HDR10
                "6d0d8de7b57e35518ac0308b0ddf404e" # DV HDR
                "1f733af03141f068a540eec352589a89" # DV HLG
                "27954b0a80aab882522a88a4d9eae1cd" # DV SDR
                "a3d82cbef5039f8d295478d28a887159" # HDR10+
                "3497799d29a085e2ac2df9d468413c94" # HDR10
                "3e2c4e748b64a1a1118e0ea3f4cf6875" # HDR
                "bb019e1cd00f304f80971c965de064dc" # HDR (undefined)
                "2a7e3be05d3861d6df7171ec74cad727" # PQ
                "17e889ce13117940092308f48b48b45b" # HLG
                "0dad0a507451acddd754fe6dc3a7f5e7" # HDR10+ Boost
                "385e9e8581d33133c3961bdcdeffb7b4" # DV HDR10+ Boost

                "496f355514737f7d83bf7aa4d24f8169" # TrueHD ATMOS
                "2f22d89048b01681dde8afe203bf2e95" # DTS X
                "417804f7f2c4308c1f4c5d380d4c4475" # ATMOS (undefined)
                "1af239278386be2919e1bcee0bde047e" # DD+ ATMOS
                "3cafb66171b47f226146a0770576870f" # TrueHD
                "dcf3ec6938fa32445f590a4da84256cd" # DTS-HD MA
                "a570d4a0e56a2874b64e5bfa55202a1b" # FLAC
                "e7c2fcae07cbada050a0af3357491d7b" # PCM
                "8e109e50e0a0b83a5098b056e13bf6db" # DTS-HD HRA
                "185f1dd7264c4562b9022d963ac37424" # DD+
                "f9f847ac70a0af62ea4a08280b859636" # DTS-ES
                "1c1a4c5e823891c75bc50380a6866f73" # DTS
                "240770601cc226190c367ef59aba7463" # AAC
                "c2998bd0d90ed5621d8df281e839436e" # DD

                "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
                "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
                "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)

                "ec8fa7296b64e8cd390a1600981f3923" # Repack/Proper
                "eb3d5cc0a2be0db205fb823640db6a3c" # Repack v2
                "44e7c4de10ae50265753082e5dc76047" # Repack v3

                "d660701077794679fd59e8bdf4ce3a29" # AMZN
                "f67c9ca88f463a48346062e8ad07713f" # ATVP
                "77a7b25585c18af08f60b1547bb9b4fb" # CC
                "36b72f59f4ea20aad9316f475f2d9fbb" # DCU
                "89358767a60cc28783cdc3d0be9388a4" # DSNP
                "a880d6abc21e7c16884f3ae393f84179" # HMAX
                "7a235133c87f7da4c8cccceca7e3c7a6" # HBO
                "f6cce30f1733d5c8194222a7507909bb" # HULU
                "0ac24a2a68a9700bcb7eeca8e5cd644c" # iT
                "81d1fbf600e2540cee87f3a23f9d3c1c" # MAX
                "d34870697c9db575f17700212167be23" # NF
                "c67a75ae4a1715f2bb4d492755ba4195" # PMTP
                "1656adc6d7bb2c8cca6acfb6592db421" # PCOK
                "ae58039e1319178e6be73caab5c42166" # SHO
                "1efe8da11bfd74fbbcd4d8117ddb9213" # STAN
                "9623c5c9cac8e939c1b9aedd32f640bf" # SYFY
                "43b3cf48cb385cd3eac608ee6bca7f09" # UHD Streaming Boost
                "d2d299244a92b8a52d4921ce3897a256" # UHD Streaming Cut

                "e6258996055b9fbab7e9cb2f75819294" # WEB Tier 01
                "58790d4e2fdcd9733aa7ae68ba2bb503" # WEB Tier 02
                "d84935abd3f8556dcd51d4f27e22d0a6" # WEB Tier 03
                "d0c516558625b04b363fa6c5c2c7cfd4" # WEB Scene
                "3a3ff47579026e76d6504ebea39390de" # Remux Tier 01
                "9f98181fe5a3fbeb0cc29340da2a468a" # Remux Tier 02
                "8baaf0b3142bf4d94c42a724f034e27a" # Remux Tier 03
              ];
              assign_scores_to = [
                { name = "Any"; }
              ];
            }
          ];
        };
      };
    };
  };

  systemd.services.recyclarr.serviceConfig.LoadCredential = [
    "radarr-api-key:${config.sops.secrets.radarr-api-key.path}"
    "sonarr-api-key:${config.sops.secrets.sonarr-api-key.path}"
  ];

  programs = {
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  networking.firewall.allowedTCPPorts = [
    80 # nginx
    54545 # qbittorrent
  ];

  system.stateVersion = "24.11";
}
