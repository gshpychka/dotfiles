{
  config,
  pkgs,
  lib,
  ...
}: let
  machineIpAddress = "192.168.1.2";
  networkInterface = "eth0";
  routerIpAddress = "192.168.1.1";
  dnsmasqPort = 5353;

  partyLightIpAddress = "192.168.1.35";
  p1sIpAddress = "192.168.1.159";
  hueIpAddress = "192.168.1.131";
  camIpAddress = "192.168.1.146";
  mediaGroup = "media";
in {
  imports = [./hardware-configuration.nix];

  boot = {
    initrd = {
      availableKernelModules = ["xhci_pci" "usbhid" "usb_storage"];
      # kernelModules = [];
    };
    kernelPackages = pkgs.linuxKernel.packages.linux_rpi4;
    # kernelModules = [];
    # extraModulePackages = [];
    # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
    loader = {
      grub.enable = false;
      # Enables the generation of /boot/extlinux/extlinux.conf
      generic-extlinux-compatible.enable = true;
    };
  };

  networking = {
    hostName = config.shared.harborHost;
    defaultGateway = routerIpAddress;
    domain = config.shared.localDomain;
    useDHCP = false;
    # TODO: figure out how to make localhost work here
    nameservers = [machineIpAddress];
    interfaces.${networkInterface}.ipv4 = {
      addresses = [
        {
          address = machineIpAddress;
          prefixLength = 24;
        }
      ];
    };
    # prevent the local FQDN from being resolved to the loopback address
    # otherwise, the DNS server will respond with the loopback address for the harbor fqdn
    hosts = lib.mkForce {};
  };

  time.timeZone = "Europe/Kyiv";

  hardware = {bluetooth.enable = true;};

  users = {
    groups.${mediaGroup} = {};
    users = {
      ${config.shared.harborUsername} = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = ["wheel" mediaGroup];
        packages = with pkgs; [neovim git];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG"
        ];
        initialHashedPassword = "";
      };
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = false;
  };

  security = {
    sudo.enable = true;
    pam = {
      sshAgentAuth.enable = true;
      services.sudo.sshAgentAuth = true;
    };
  };

  services = let
    frontendServices = {
      home-assistant = {
        subdomain = "hass";
        port = 8123;
      };
      adguard = {
        subdomain = "adguard";
        port = 3000;
      };
      deluge = {
        subdomain = "deluge";
        port = 8112;
      };
      mqtt = {
        subdomain = "mqtt";
        port = 1883;
      };
    };
  in {
    # argononed fails to start
    # hardware.argonone.enable = true;
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
      ports = [config.shared.harborSshPort];
    };
    dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        interface = networkInterface;
        domain = config.networking.domain;
        local = "/${config.networking.domain}/";
        no-resolv = true;
        no-hosts = true;
        listen-address = "127.0.0.1";
        port = dnsmasqPort;
        # resolve all subdomains to the machine IP address
        address = let
          subdomains =
            pkgs.lib.mapAttrsToList
            (name: serviceConfig: serviceConfig.subdomain)
            frontendServices;
        in
          (map (subdomain: "/${subdomain}.${config.networking.fqdn}/${machineIpAddress}")
            subdomains)
          ++ ["/${config.networking.fqdn}/${machineIpAddress}"];
        dhcp-range = "${networkInterface},192.168.1.3,192.168.1.254,24h";
        dhcp-option = [
          "option:router,${config.networking.defaultGateway.address}"
          "option:domain-name,${config.networking.domain}"
          "option:dns-server,${machineIpAddress}"
        ];
        dhcp-host = [
          "00:17:88:A4:FF:6B,hue,${hueIpAddress}"
          "04:17:B6:4B:FC:F7,cam,${camIpAddress}"
          "7C:87:CE:9F:30:E0,p1s,${p1sIpAddress}"
        ];
      };
    };
    nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts =
        pkgs.lib.mapAttrs (name: subdomainConfig: {
          serverName = "${subdomainConfig.subdomain}.${config.networking.fqdn}";
          addSSL = false;
          extraConfig = ''
            proxy_buffering off;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString subdomainConfig.port}";
            proxyWebsockets = true;
          };
        })
        frontendServices;
    };
    plex = {
      enable = true;
      openFirewall = true;
      group = mediaGroup;
    };
    mosquitto = {
      enable = true;
      listeners = [
        {
          port = frontendServices.mqtt.port;
          address = "127.0.0.1";
          users = {
            # TODO: need to set up secrets to use password auth
            # this is not working as written
            reaper = {
              acl = ["readwrite reaper/#"];
            };
            hass = {
              acl = ["read #"];
            };
          };
        }
      ];
    };

    home-assistant = {
      enable = true;
      openFirewall = false;
      extraPackages = python3Packages: with python3Packages; [aiohomekit python-otbr-api];
      extraComponents = [
        "adguard"
        "plex"
        "asuswrt"
        "deluge"
        "ukraine_alarm"
        "xiaomi_miio"
        "xiaomi_aqara"
        "smartthings"
        "homekit"
        "hue"
        "cast"
        "androidtv"
        "androidtv_remote"
        "samsungtv"
        "xbox"
        "zha"
        "mqtt"
        "openai"
        "ollama"
        "esphome"
      ];
      customComponents = with pkgs.home-assistant-custom-components; [
        samsungtv-smart
      ];
      config = {
        http = {
          server_host = ["127.0.0.1"];
          server_port = frontendServices.home-assistant.port;
          use_x_forwarded_for = true;
          trusted_proxies = ["127.0.0.1"];
        };
        mqtt = {
          sensor = [
            {
              name = "CPU temperature";
              state_topic = "reaper/cpu/temperature";
              device = {
                name = "reaper";
                identifiers = ["reaper"];
              };
              device_class = "temperature";
              expire_after = 60;
              icon = "mdi:temperature-celsius";
              state_class = "measurement";
              unique_id = "reaper_cpu_temperature";
              unit_of_measurement = "°C";
            }
          ];
        };
        "automation ui" = "!include automations.yaml";
        "automation manual" = let
          typeSubtypeMapping = {
            "short_press" = rec {
              type = "remote_button_short_press";
              subtype = type;
            };
            "double_press" = rec {
              type = "remote_button_double_press";
              subtype = type;
            };
            "triple_press" = rec {
              type = "remote_button_triple_press";
              subtype = type;
            };
            "quadruple_press" = rec {
              type = "remote_button_quadruple_press";
              subtype = type;
            };
            "quintiple_press" = rec {
              type = "remote_button_quintiple_press";
              subtype = type;
            };
            "long_press" = {
              type = "remote_button_long_press";
              subtype = "button";
            };
          };

          generateTriggers = friendlyName: ids: let
            pressType = typeSubtypeMapping.${friendlyName}.type;
            subtype = typeSubtypeMapping.${friendlyName}.subtype;
          in
            map (id: {
              device_id = id;
              domain = "zha";
              platform = "device";
              type = pressType;
              subtype = subtype;
            })
            ids;
          room_main_button = "f9a2c8da0e0721bc4ada9499dc357ab6";
          kitchen_main_button = "c6bdd13c04cdd58c2ab0156d17182f4a";
          kitchen_table_button = "8cfc8a2d9ce6e04b6b64170468a720df";
          bed_button = "af8ce34221de2bff3f23f770a598284b";
          couch_table_button = "b6f88867d1432418f39d644748ba3e36";
          extra_button_0 = "5e6ef78d4e10592be1d70f43a64a02f6";

          room_lights = "c15a46c9c5ed4c9c370e1027cb23124b";
          kitchen_lights = "7fd4114f73ccae38ffe7eab9fce35274";
          kitchen_aux_light = "75849e0f307bbb353c0a78c9c206f5ce";
          bed_light = "068376822da7ebb5ec671613f607f089";

          room_buttons = [room_main_button bed_button couch_table_button];
          kitchen_buttons = [kitchen_main_button kitchen_table_button];

          purifier = "c58ebba338d6c7cd8a1aca9007fb6e5d";
        in [
          (let
            pressTypeMapping = {
              "short_press" = kitchen_buttons;
              "quadruple_press" = room_buttons;
            };
          in {
            alias = "kitchen lights toggle";
            trigger = builtins.concatMap (pressType:
              generateTriggers pressType pressTypeMapping.${pressType})
            (builtins.attrNames pressTypeMapping);
            action = [
              {
                type = "toggle";
                device_id = kitchen_lights;
                entity_id = "light.kitchen";
                domain = "light";
              }
            ];
            mode = "single";
          })
          (let
            pressTypeMapping = {
              "short_press" = room_buttons;
              "quadruple_press" = kitchen_buttons;
            };
          in {
            alias = "room lights toggle";
            trigger = builtins.concatMap (pressType:
              generateTriggers pressType pressTypeMapping.${pressType})
            (builtins.attrNames pressTypeMapping);
            action = [
              {
                type = "toggle";
                device_id = room_lights;
                entity_id = "light.room";
                domain = "light";
              }
            ];
            mode = "single";
          })
          (let
            pressTypeMapping = {"double_press" = room_buttons;};
          in {
            alias = "room lights full brightness";
            trigger = builtins.concatMap (pressType:
              generateTriggers pressType pressTypeMapping.${pressType})
            (builtins.attrNames pressTypeMapping);
            action = [
              {
                type = "turn_on";
                device_id = room_lights;
                entity_id = "light.room";
                domain = "light";
                brightness_pct = 100;
              }
            ];
          })
          (let
            pressTypeMapping = {"double_press" = kitchen_buttons;};
          in {
            alias = "kitchen lights full brightness";
            trigger = builtins.concatMap (pressType:
              generateTriggers pressType pressTypeMapping.${pressType})
            (builtins.attrNames pressTypeMapping);
            action = [
              {
                type = "turn_on";
                device_id = kitchen_lights;
                entity_id = "light.kitchen";
                domain = "light";
                brightness_pct = 100;
              }
            ];
          })
          (let
            pressTypeMapping = {"triple_press" = kitchen_buttons;};
          in {
            alias = "kitchen aux light toggle";
            trigger = builtins.concatMap (pressType:
              generateTriggers pressType pressTypeMapping.${pressType})
            (builtins.attrNames pressTypeMapping);
            action = [
              {
                type = "toggle";
                device_id = kitchen_aux_light;
                # TODO: rename entity
                entity_id = "light.reading_light";
                domain = "light";
              }
            ];
          })
          (let
            pressTypeMapping = {"long_press" = [bed_button];};
          in {
            alias = "bed light toggle";
            trigger = builtins.concatMap (pressType:
              generateTriggers pressType pressTypeMapping.${pressType})
            (builtins.attrNames pressTypeMapping);
            action = [
              {
                type = "toggle";
                device_id = bed_light;
                entity_id = "light.bed_light";
                domain = "light";
              }
            ];
          })
          {
            alias = "turn on purifier";
            trigger = [
              {
                type = "pm25";
                platform = "device";
                device_id = purifier;
                entity_id = "sensor.purifier_pm2_5";
                domain = "sensor";
                above = 20;
              }
            ];
            condition = [
              {
                condition = "device";
                device_id = purifier;
                domain = "fan";
                entity_id = "fan.purifier";
                type = "is_off";
              }
            ];
            action = [
              {
                type = "turn_on";
                device_id = purifier;
                entity_id = "fan.purifier";
                domain = "fan";
              }
            ];
          }
          {
            alias = "turn off purifier";
            trigger = [
              {
                type = "pm25";
                platform = "device";
                device_id = purifier;
                entity_id = "sensor.purifier_pm2_5";
                domain = "sensor";
                below = 10;
              }
            ];
            condition = [
              {
                condition = "device";
                device_id = purifier;
                domain = "fan";
                entity_id = "fan.purifier";
                type = "is_on";
              }
            ];
            action = [
              {
                type = "turn_off";
                device_id = purifier;
                entity_id = "fan.purifier";
                domain = "fan";
              }
            ];
          }
        ];

        default_config = {};
      };
    };
    adguardhome = {
      enable = true;
      mutableSettings = false;
      # only affects the web interface port
      openFirewall = false;
      settings = {
        users = [
          {
            name = "glib";
            password = "$2y$05$y0ENgc6LYa.yRCgtTG9eneZJTimtnlGV6AaIFNbp71byq/Qtn6Oru";
          }
        ];
        http = {
          address = "127.0.0.1:${toString frontendServices.adguard.port}";
        };
        theme = "dark";
        dns = {
          bind_hosts = [machineIpAddress];
          filtering = {
            filtering_enabled = true;
            blocked_response_ttl = 60 * 60 * 24;
            safe_search = {enabled = false;};
          };
          ratelimit = 0;
          upstream_dns = [
            "tls://1dot1dot1dot1.cloudflare-dns.com"
            "[/${config.networking.domain}/]127.0.0.1:${
              toString dnsmasqPort
            }"
            "[/wpad.${config.networking.domain}/]#"
            "[/lb._dns-sd._udp.${config.networking.domain}/]#"
          ];
          allowed_clients = ["${routerIpAddress}/24" "127.0.0.1/32"];
          bootstrap_dns = ["1.1.1.1" "1.0.0.1"];
          aaaa_disabled = true;
          upstream_timeout = "1s";
          all_servers = true;
          use_http3_upstreams = true;
          enable_dnssec = true;
          # 50 MBytes
          cache_size = 1024 * 1024 * 50;
        };
        dhcp = {enabled = false;};
        clients = {runtime_sources = {hosts = false;};};
      };
    };
    deluge = {
      enable = true;
      declarative = true;
      group = mediaGroup;
      # we don't allow remote connections anyway, password doesn't need to be secure
      authFile = builtins.toFile "auth" "localclient:deluge:10\n";
      web = {
        enable = true;
        port = frontendServices.deluge.port;
      };
      config = {
        # required for webui, only from localhost due to firewall
        allow_remote = true;
        pre_allocate_storage = true;
        enabled_plugins = ["autoadd"];
        download_location = "/mnt/torrents";
        torrentfiles_location = "/mnt/torrents";
        move_completed = true;
        move_completed_path = "/mnt/media";
        max_upload_speed = 0;
        stop_seed_at_ratio = true;
        remove_seed_at_ratio = true;
        stop_seed_ratio = 0;
        new_release_check = false;
        max_active_limit = 10;
        max_active_downloading = 10;
        max_active_seeding = 0;
      };
    };
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [80];
  networking.firewall.allowedUDPPorts = [53 67];

  system.stateVersion = "22.11";
}
