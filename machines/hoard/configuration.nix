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
    nzbget = "6789";
    sonarr = "8989";
    radarr = "7878";
    lidarr = "8686";
    prowlarr = "9696";
    plex = "32400";
  };
in
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
    templates = {
      "homepage-dashboard.env" = {
        content = ''
          HOMEPAGE_VAR_RADARR_API_KEY=${config.sops.placeholder.radarr-api-key}
          HOMEPAGE_VAR_SONARR_API_KEY=${config.sops.placeholder.sonarr-api-key}
          HOMEPAGE_VAR_LIDARR_API_KEY=${config.sops.placeholder.lidarr-api-key}
          HOMEPAGE_VAR_PROWLARR_API_KEY=${config.sops.placeholder.prowlarr-api-key}
          HOMEPAGE_VAR_QBITTORRENT_USERNAME=${config.sops.placeholder.qbittorrent-username}
          HOMEPAGE_VAR_QBITTORRENT_PASSWORD=${config.sops.placeholder.qbittorrent-password}
          HOMEPAGE_VAR_NZBGET_USERNAME=${config.sops.placeholder.nzbget-username}
          HOMEPAGE_VAR_NZBGET_PASSWORD=${config.sops.placeholder.nzbget-password}
          HOMEPAGE_VAR_PLEX_TOKEN=${config.sops.placeholder.plex-token}
        '';
        restartUnits = [ config.systemd.services.homepage-dashboard.name ];
        mode = "0400";
      };
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
        nzbget = {
          serverName = "nzbget.${config.networking.fqdn}";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${ports.nzbget}/";
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
            {
              "nzbget" = {
                icon = "nzbget";
                href = "http://nzbget.${config.networking.fqdn}";
                widgets = [
                  {
                    type = "nzbget";
                    url = "http://127.0.0.1:${ports.nzbget}";
                    username = "{{HOMEPAGE_VAR_NZBGET_USERNAME}}";
                    password = "{{HOMEPAGE_VAR_NZBGET_PASSWORD}}";
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
          base_url = "http://localhost:${ports.radarr}";
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
                "1bef6c151fa35093015b0bfef18279e5" # 2160p
                "290078c8b266272a5cc8e251b5e2eb0b" # 1080p
                "c99279ee27a154c2f20d1d505cc99e25" # 720p

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
                "ef4963043b0987f8485bc9106f16db38" # DV (Disk)

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

  systemd.services = {
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
