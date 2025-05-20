{
  config,
  pkgs,
  ...
}:
let
  ports = {
    glances = toString config.services.glances.port;
    qbittorrent = toString config.services.qbittorrent.port;
    homepage = toString config.services.homepage-dashboard.listenPort;
    sabnzbd = "8085";
    sonarr = "8989";
    radarr = "7878";
    lidarr = "8686";
    prowlarr = "9696";
    plex = "32400";
    tautulli = config.services.tautulli.port;
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/qbittorrent.nix
    ../../modules/sabnzbd.nix
  ];

  boot = {
    loader = {
      grub.enable = false;
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      # SSH in initrd for LUKS unlocking
      network = {
        enable = true;
        ssh = {
          enable = true;
          hostKeys = [
            # These keys were generated imperatively, they are no the regular host keys.
            # Justification from the docs:

            # Unless your bootloader supports initrd secrets,
            # these keys are stored insecurely in the global Nix store.
            # Do NOT use your regular SSH host private keys for this purpose or you’ll expose them to regular users!

            # ssh-keygen -t ed25519 -N "" -f /etc/secrets/initrd/ssh_host_ed25519_key
            "/etc/secrets/initrd/ssh_host_ed25519_key"

            # ssh-keygen -t rsa -N "" -f /etc/secrets/initrd/ssh_host_rsa_key
            "/etc/secrets/initrd/ssh_host_rsa_key"
          ];
          port = 22;
          authorizedKeys = config.users.users.gshpychka.openssh.authorizedKeys.keys;
          authorizedKeyFiles = config.users.users.gshpychka.openssh.authorizedKeys.keyFiles;
        };
      };
    };

    kernelPackages = pkgs.linuxPackages;
    kernelParams = [
      # enable mq io schedulers
      "scsi_mod.use_blk_mq=1"
      "dm_mod.use_blk_mq=1"
      # force-enable SAT mode with UAS driver for Seagate enclosure
      # https://www.smartmontools.org/wiki/SAT-with-UAS-Linux#workaround-unset-t
      "usb-storage.quirks=0bc2:2032:"
    ];
    kernel.sysctl = {
      "kernel.task_delayacct" = "1"; # Enables task delay accounting at runtime (additional stats in e.g. iotop)
      "vm.dirty_background_ratio" = "10"; # Start flushing dirty pages when 10% of memory is dirty
      "vm.dirty_ratio" = "80"; # Force flushing dirty pages when 80% of memory is dirty
      "vm.vfs_cache_pressure" = "10"; # Something to do with storing fs metadata in memory
      "vm.dirty_writeback_centisecs" = "500"; # Writeback every 5s
      "vm.dirty_expire_centisecs" = "500"; # Expire dirty pages every 5s
    };
    tmp = {
      useTmpfs = true; # /tmp is stored in RAM
      tmpfsSize = "80%"; # /tmp can take up to 80% of RAM
    };
  };
  environment.systemPackages = with pkgs; [
    cryptsetup
  ];

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
      plex-token = { };
    };
    templates = {
      "homepage-dashboard.env" = {
        content = ''
          HOMEPAGE_VAR_RADARR_API_KEY=${config.sops.placeholder.radarr-api-key}
          HOMEPAGE_VAR_SONARR_API_KEY=${config.sops.placeholder.sonarr-api-key}
          HOMEPAGE_VAR_LIDARR_API_KEY=${config.sops.placeholder.lidarr-api-key}
          HOMEPAGE_VAR_PROWLARR_API_KEY=${config.sops.placeholder.prowlarr-api-key}
          HOMEPAGE_VAR_QBITTORRENT_USERNAME=${config.sops.placeholder.qbittorrent-username}
          HOMEPAGE_VAR_QBITTORRENT_PASSWORD=${config.sops.placeholder.qbittorrent-password}
          HOMEPAGE_VAR_PLEX_TOKEN=${config.sops.placeholder.plex-token}
        '';
        restartUnits = [ config.systemd.services.homepage-dashboard.name ];
        mode = "0400";
      };
    };
  };

  # Wi-Fi
  # sops.secrets.wifi-psk = {
  #   sopsFile = ../../secrets/common/network.yaml;
  #   key = "main-wifi-psk";
  # };
  # sops.templates."wireless.conf" = {
  #   content = ''
  #     psk=${config.sops.placeholder.wifi-psk}
  #   '';
  #   mode = "0400";
  # };
  # networking.wireless = {
  #   enable = true;
  #   secretsFile = config.sops.templates."wireless.conf".path;
  #   networks = {
  #     "YourNewNeighbor" = {
  #       pskRaw = "ext:psk";
  #     };
  #   };
  #   scanOnLowSignal = false;
  # };

  networking = {
    hostName = "hoard";
    domain = "lan";
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
        extraGroups = [
          "wheel"
          "plugdev"
          "usb"
        ];
        packages = with pkgs; [
          git
          sysstat
          iotop
          unrar
          bcc
          ffmpeg-headless
          fio
          smartmontools
        ];
        openssh.authorizedKeys.keys = [
          # eve
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG"
        ];
        # TODO: sops-nix
        initialHashedPassword = "";
      };
      "time-machine" = {
        group = config.users.groups.media.name;
        isSystemUser = true;
      };
      "kodi" = {
        group = config.users.groups.media.name;
        isSystemUser = true;
      };
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = false;
    enableBashCompletion = false;
    enableLsColors = false;
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
        };
        "kodi" = {
          "path" = "/mnt/hoard/plex";
          "valid users" = "kodi";
          "public" = "no";
          "writable" = "yes";
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
            proxyPass = "http://127.0.0.1:${ports.qbittorrent}/";
          };
        };
        prowlarr = {
          serverName = "prowlarr.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${ports.prowlarr}/";
          };
        };
        sonarr = {
          serverName = "sonarr.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${ports.sonarr}/";
          };
        };
        radarr = {
          serverName = "radarr.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${ports.radarr}/";
          };
        };
        lidarr = {
          serverName = "lidarr.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${ports.lidarr}/";
          };
        };
        sabnzbd = {
          serverName = "sabnzbd.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${ports.sabnzbd}/";
          };
        };
        homepage = {
          serverName = "home.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${ports.homepage}/";
          };
        };
        glances = {
          serverName = "glances.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${ports.glances}/";
          };
        };
        tautulli = {
          serverName = "tautulli.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${ports.tautulli}/";
          };
        };
      };
    };
    homepage-dashboard = {
      enable = true;
      settings = {
        title = config.networking.hostName;
      };
      allowedHosts = config.services.nginx.virtualHosts.homepage.serverName;
      environmentFile = config.sops.templates."homepage-dashboard.env".path;
      widgets = [
        {
          glances = {
            url = "http://127.0.0.1:${ports.glances}";
            version = 4;
            cputemp = true;
            uptime = true;
            disk = [
              "/mnt/hoard"
              "/mnt/oasis"
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
                icon = "plex";
                href = "https://app.plex.tv";
                widgets = [
                  {
                    type = "plex";
                    url = "http://127.0.0.1:${ports.plex}";
                    key = "{{HOMEPAGE_VAR_PLEX_TOKEN}}";
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
                icon = "qbittorrent";
                href = "http://qbittorrent.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "qbittorrent";
                    url = "http://127.0.0.1:${ports.qbittorrent}";
                    username = "{{HOMEPAGE_VAR_QBITTORRENT_USERNAME}}";
                    password = "{{HOMEPAGE_VAR_QBITTORRENT_PASSWORD}}";
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
                icon = "sonarr";
                href = "http://sonarr.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "sonarr";
                    url = "http://127.0.0.1:${ports.sonarr}";
                    key = "{{HOMEPAGE_VAR_SONARR_API_KEY}}";
                  }
                ];
              };
            }
            {
              "Radarr" = {
                icon = "radarr";
                href = "http://radarr.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "radarr";
                    url = "http://127.0.0.1:${ports.radarr}";
                    key = "{{HOMEPAGE_VAR_RADARR_API_KEY}}";
                  }
                ];
              };
            }
            {
              "Lidarr" = {
                icon = "lidarr";
                href = "http://lidarr.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "lidarr";
                    url = "http://127.0.0.1:${ports.lidarr}";
                    key = "{{HOMEPAGE_VAR_LIDARR_API_KEY}}";
                  }
                ];
              };
            }
            {
              "Prowlarr" = {
                icon = "prowlarr";
                href = "http://prowlarr.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "prowlarr";
                    url = "http://127.0.0.1:${ports.prowlarr}";
                    key = "{{HOMEPAGE_VAR_PROWLARR_API_KEY}}";
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
      extraArgs = [
        "--webserver"
        "--disable-webui"
        "--disable-check-update"
        "--diskio-iops"
        "--hide-kernel-threads"
        "--fs-free-space"
      ];
    };
    fstrim.enable = true;
    plex = {
      enable = true;
      openFirewall = true;
      group = "media";
    };
    tautulli = {
      enable = true;
      user = "tautulli";
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
    sabnzbd = {
      enable = true;
      group = "media";
    };
    recyclarr = {
      enable = true;
      group = "media";
      configuration = {
        radarr.radarr = {
          api_key._secret = "/run/credentials/recyclarr.service/radarr-api-key";
          base_url = "http://localhost:${ports.radarr}";
          delete_old_custom_formats = true;
          replace_existing_custom_formats = true;
          quality_profiles = [
            {
              name = "Any";
              min_format_score = 0;
              upgrade = {
                allowed = true;
                until_quality = "Remux-2160p";
                until_score = 10000;
              };
            }
          ];
          custom_formats = [
            {
              trash_ids = [
                # "fb392fb0d61a010ae38e49ceaa24a1ef" # 2160p
                # "820b09bb9acbfde9c35c71e0e565dad8" # 1080p
                # "b2be17d608fc88818940cd1833b0b24c" # 720p

                "c53085ddbd027d9624b320627748612f" # DV HDR10+
                "e23edd2482476e595fb990b12e7c609c" # DV HDR10
                "58d6a88f13e2db7f5059c41047876f00" # DV
                "55d53828b9d81cbe20b02efd00aa0efd" # DV HLG
                "a3e19f8f627608af0211acd02bf89735" # DV SDR
                "b974a6cd08c1066250f1f177d7aa1225" # HDR10+
                "dfb86d5941bc9075d6af23b09c2aeecd" # HDR10
                "e61e28db95d22bedcadf030b8f156d96" # HDR
                "2a4d9069cc1fe3242ff9bdaebed239bb" # HDR (undefined)
                "08d6d8834ad9ec87b1dc7ec8148e7a1f" # PQ
                "9364dd386c9b4a1100dde8264690add7" # HLG
                "b17886cb4158d9fea189859409975758" # HDR10+ Boost
                "55a5b50cb416dea5a50c4955896217ab" # DV HDR10+ Boost
                # "f700d29429c023a5734505e77daeaea7" # DV (Disk)

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
                "6ba9033150e7896bdc9ec4b44f2b230f" # MP3
                "a061e2e700f81932daf888599f8a8273" # OPUS

                "3a3ff47579026e76d6504ebea39390de" # Remux Tier 01
                "9f98181fe5a3fbeb0cc29340da2a468a" # Remux Tier 02
                "8baaf0b3142bf4d94c42a724f034e27a" # Remux Tier 03
                "c20f169ef63c5f40c2def54abaf4438e" # WEB Tier 01
                "403816d65392c79236dcb6dd591aeda4" # WEB Tier 02
                "af94e0fe497124d1f9ce732069ec8c3b" # WEB Tier 03
                "e7718d7a3ce595f289bfee26adc178f5" # Repack/Proper
                "ae43b294509409a6a13919dedd4764c4" # Repack2
                "5caaaa1c08c1742aa4342d8c4cc463f2" # Repack3

                "b3b3a6ac74ecbd56bcdbefa4799fb9df" # AMZN
                "40e9380490e748672c2522eaaeb692f7" # ATVP
                "cc5e51a9e85a6296ceefe097a77f12f4" # BCORE
                "16622a6911d1ab5d5b8b713d5b0036d4" # CRiT
                "84272245b2988854bfb76a16e60baea5" # DSNP
                "509e5f41146e278f9eab1ddaceb34515" # HBO
                "5763d1b0ce84aff3b21038eea8e9b8ad" # HMAX
                "526d445d4c16214309f0fd2b3be18a89" # Hulu
                "e0ec9672be6cac914ffad34a6b077209" # iT
                "6a061313d22e51e0f25b7cd4dc065233" # MAX
                "2a6039655313bf5dab1e43523b62c374" # MA
                "170b1d363bd8516fbf3a3eb05d4faff6" # NF
                "e36a0ba1bc902b26ee40818a1d59b8bd" # PMTP
                "c9fd353f8f5f1baf56dc601c4cb29920" # PCOK
                "c2863d2a50c9acad1fb50e53ece60817" # STAN

                "0f12c086e289cf966fa5948eac571f44" # Hybrid
                "570bc9ebecd92723d2d21500f4be314c" # Remaster
                "eca37840c13c6ef2dd0262b141a5482f" # 4K Remaster
                "e0c07d59beb37348e975a930d5e50319" # Criterion Collection
                "9d27d9d2181838f76dee150882bdc58c" # Masters of Cinema
                "db9b4c4b53d312a3ca5f1378f6440fc9" # Vinegar Syndrome
                "957d0f44b592285f26449575e8b1167e" # Special Edition
                "eecf3a857724171f968a66cb5719e152" # IMAX
                "9f6cbff8cfe4ebbc1bde14c7b7bec0de" # IMAX Enhanced

                # unwanted
                "ed38b889b31be83fda192888e2286d83" # BR-DISK
                "e6886871085226c3da1830830146846c" # Generated Dynamic HDR
                "90a6f9a284dff5103f6346090e6280c8" # LQ
                "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
                "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
                "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
                "0a3f082873eb454bde444150b70253cc" # Extras
                "712d74cd88bceb883ee32f773656b1f5" # Sing-Along Versions
                "cae4ca30163749b891686f95532519bd" # AV1
                "923b6abef9b17f937fab56cfcf89e1f1" # DV (WEBDL)
                "b6832f586342ef70d9c128d40c07b872" # Bad Dual Groups
                "cc444569854e9de0b084ab2b8b1532b2" # Black and White Editions
                # "ae9b7c9ebde1f3bd336a8cbd1ec4c5e5" # No-RlsGroup
                # "7357cf5161efbf8c4d5d0c30b4815ee2" # Obfuscated
                "5c44f52a8714fdd79bb4d98e2673be1f" # Retags
                # "f537cf427b64c38c8e36298f657e4828" # Scene
                # "9c38ebb7384dada637be8899efa68e6f" # SDR
                "25c12f78430a3a23413652cbd1d48d77" # SDR (no WEBDL)
                "839bea857ed2c0a8e084f3cbdbd65ecb" # x265 (no HDR/DV)
              ];
              assign_scores_to = [
                { name = "Any"; }
              ];
            }
          ];
        };
        sonarr.sonarr = {
          api_key._secret = "/run/credentials/recyclarr.service/sonarr-api-key";
          base_url = "http://localhost:${ports.sonarr}";
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
                # "1bef6c151fa35093015b0bfef18279e5" # 2160p
                # "290078c8b266272a5cc8e251b5e2eb0b" # 1080p
                # "c99279ee27a154c2f20d1d505cc99e25" # 720p

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

                "0d7824bb924701997f874e7ff7d4844a" # TrueHD ATMOS
                "9d00418ba386a083fbf4d58235fc37ef" # DTS X
                "b6fbafa7942952a13e17e2b1152b539a" # ATMOS (undefined)
                "4232a509ce60c4e208d13825b7c06264" # DD+ ATMOS
                "1808e4b9cee74e064dfae3f1db99dbfe" # TrueHD
                "c429417a57ea8c41d57e6990a8b0033f" # DTS-HD MA
                "851bd64e04c9374c51102be3dd9ae4cc" # FLAC
                "30f70576671ca933adbdcfc736a69718" # PCM
                "cfa5fbd8f02a86fc55d8d223d06a5e1f" # DTS-HD HRA
                "63487786a8b01b7f20dd2bc90dd4a477" # DD+
                "c1a25cd67b5d2e08287c957b1eb903ec" # DTS-ES
                "5964f2a8b3be407d083498e4459d05d0" # DTS
                "a50b8a0c62274a7c38b09a9619ba9d86" # AAC
                "dbe00161b08a25ac6154c55f95e6318d" # DD
                "3e8b714263b26f486972ee1e0fe7606c" # MP3
                "28f6ef16d61e2d1adfce3156ed8257e3" # Opus

                "3a4127d8aa781b44120d907f2cd62627" # Hybrid
                "b735f09d3c025cbb7d75a5d38325b73b" # Remaster
                "ec8fa7296b64e8cd390a1600981f3923" # Repack/Proper
                "eb3d5cc0a2be0db205fb823640db6a3c" # Repack v2
                "44e7c4de10ae50265753082e5dc76047" # Repack v3
                "3bc5f395426614e155e585a2f056cdf1" # Season Pack

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
                "9965a052eb87b0d10313b1cea89eb451" # Remux Tier 01
                "8a1d0c3d7497e741736761a1da866a2e" # Remux Tier 02
                "d6819cba26b1a6508138d25fb5e32293" # HD Bluray Tier 01
                "c2216b7b8aa545dc1ce8388c618f8d57" # HD Bluray Tier 02

                # unwanted
                "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
                "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
                "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)
                "23297a736ca77c0fc8e70f8edd7ee56c" # Upscaled
                "9b27ab6498ec0f31a3353992e19434ca" # DV (WEBDL)
                "83304f261cf516bb208c18c54c0adf97" # SDR (no WEBDL)
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

  systemd = {
    slices = {
      media = {
        sliceConfig = {
          IOAccounting = "yes";
          IODeviceWeight = "/mnt/hoard 10";
        };
        unitConfig = {
          RequiresMountsFor = [
            "/mnt/oasis"
            "/mnt/hoard"
          ];
        };
      };
      system-samba = {
        # extend existing slice
        unitConfig = {
          RequiresMountsFor = [
            "/mnt/hoard"
          ];
        };
        sliceConfig = {
          IOAccounting = "yes";
          IODeviceWeight = "/mnt/hoard 100";
        };
      };
    };
    services = {
      recyclarr = {
        after = [
          config.systemd.services.radarr.name
          config.systemd.services.sonarr.name
        ];
        serviceConfig.LoadCredential = [
          "radarr-api-key:${config.sops.secrets.radarr-api-key.path}"
          "sonarr-api-key:${config.sops.secrets.sonarr-api-key.path}"
        ];
      };
      sabnzbd = {
        serviceConfig = {
          Slice = "media.slice";
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = "6";
        };
      };
      qbittorrent = {
        serviceConfig = {
          Slice = "media.slice";
          IOSchedulingClass = "idle";
        };
      };
      plex = {
        unitConfig = {
          RequiresMountsFor = [ "/mnt/hoard" ];
        };
        serviceConfig = {
          IODeviceWeight = "/mnt/hoard 1200";
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = "2";
        };
      };
      radarr.serviceConfig = {
        Slice = "media.slice";
        IOSchedulingClass = "idle";
      };
      sonarr.serviceConfig = {
        Slice = "media.slice";
        IOSchedulingClass = "idle";
      };
      lidarr.serviceConfig = {
        Slice = "media.slice";
        IOSchedulingClass = "idle";
      };
      prowlarr.serviceConfig = {
        Slice = "media.slice";
        IOSchedulingClass = "idle";
      };

      # glances = {
      #   serviceConfig = {
      #     EnvironmentFile = config.sops.templates."glances.env".path;
      #     ExecStart = lib.mkForce (
      #       # figure out how to set the password (not via CLI)
      #       toString (
      #         pkgs.writeShellScript "glances-start" ''
      #           exec ${config.services.glances.package}/bin/glances \
      #             --port ${toString config.services.glances.port} \
      #             --username \
      #             -u "$GLANCES_USERNAME" \
      #             --password "$GLANCES_PASSWORD" \
      #             ${utils.escapeSystemdExecArgs config.services.glances.extraArgs}
      #         ''
      #       )
      #     );
      #   };
      # };
    };
  };

  programs = {
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  networking.firewall.allowedTCPPorts = [
    config.services.nginx.defaultHTTPListenPort
    54545 # qbittorrent
  ];

  system.stateVersion = "24.11";
}
