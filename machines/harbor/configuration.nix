{ config, pkgs, ... }:

let
  machineIpAddress = "192.168.1.2";
  networkInterface = "eth0";
  routerIpAddress = "192.168.1.1";
  dnsmasqPort = 5353;

  party_light_address = "192.168.1.35";
in

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  networking = {
    hostName = config.shared.harborHost;
    defaultGateway = routerIpAddress;
    domain = config.shared.localDomain;
    useDHCP = false;
    nameservers = [ machineIpAddress ];
    interfaces.${networkInterface}.ipv4 = {
      addresses = [
        {
          address = machineIpAddress;
          prefixLength = 24;
        }
      ];
    };
  };

  time.timeZone = "Europe/Kiev";

  hardware = {
    bluetooth.enable = true;
  };

  users.users.${config.shared.harborUsername} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      neovim
      git
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG"
    ];
    initialHashedPassword = "";
  };

  security = {
    sudo.enable = true;
    pam = {
      enableSSHAgentAuth = true;
      services.sudo.sshAgentAuth = true;
    };
    acme.acceptTerms = true;
  };


  services =
    let
      frontendServices = {
        home-assistant = { subdomain = "hass"; port = 8123; useSSL = true; };
        plex = { subdomain = "plex"; port = 32400; useSSL = false; };
        adguard = { subdomain = "adguard"; port = 2999; useSSL = true; };
      };
    in
    {
      # argononed fails to start
      # hardware.argonone.enable = true;
      openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
        ports = [ config.shared.harborSshPort ];
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
          address =
            let
              subdomains = pkgs.lib.attrValues pkgs.lib.mapAttrs (name: serviceConfig: serviceConfig.subdomain) frontendServices;
            in
            (map (subdomain: "/${subdomain}.${config.networking.fqdn}/${machineIpAddress}") subdomains) ++ [
              "/${config.networking.fqdn}/${machineIpAddress}"
            ];
          dhcp-range = "${networkInterface},192.168.1.3,192.168.1.254,24h";
          dhcp-option = [
            "option:router,${config.networking.defaultGateway.address}"
            "option:domain-name,${config.networking.domain}"
            "option:dns-server,${machineIpAddress}"
          ];
          dhcp-host = [
            "00:17:88:A4:FF:6B,hue,192.168.1.131"
            "5C:E5:0C:AD:6A:7B,party-light,${party_light_address}"
          ];
        };
      };
      nginx = {
        enable = true;
        recommendedProxySettings = true;
        virtualHosts = pkgs.lib.mapAttrs
          (name: subdomainConfig: {
            serverName = "${subdomainConfig.subdomain}.${config.networking.fqdn}";
            forceSSL = subdomainConfig.useSSL;
            enableACME = subdomainConfig.useSSL;
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
        openFirewall = false;
      };
      deluge = {
        enable = true;
        declarative = true;
        openFirewall = true;
        config = {
          download_location = "/mnt/ssd/torrents";
          allow_remote = true;
        };
        authFile = "/var/lib/deluge/auth";
      };
      home-assistant = {
        enable = true;
        openFirewall = false;
        extraPackages = python3Packages: with python3Packages; [
          aiohomekit
        ];
        extraComponents = [
          "adguard"
          "xiaomi_miio"
          "xiaomi_aqara"
          "hue"
          "homekit"
          "apple_tv"
          "plex"
          "cast"
          "ukraine_alarm"
          "zha"
          "upnp"
          "thread"
          "androidtv"
          "androidtv_remote"
        ];
        config = {
          http = {
            server_host = [ "127.0.0.1" ];
            server_port = frontendServices.home-assistant.port;
            use_x_forwarder_for = true;
            trusted_proxies = [ "127.0.0.1" ];
          };
          sensor = [
            {
              platform = "systemmonitor";
              resources = [
                { type = "memory_use"; }
                { type = "disk_use_percent"; }
                { type = "processor_use"; }
                { type = "processor_temperature"; }
              ];
            }
          ];
          yeelight = {
            devices = {
              ${party_light_address} = {
                name = "Party light";
                model = "color";
              };
            };
          };
          "automation ui" = "!include automations.yaml";
          "automation manual" =
            let
              typeSubtypeMapping = {
                "short_press" = rec { type = "remote_button_short_press"; subtype = type; };
                "double_press" = rec { type = "remote_button_double_press"; subtype = type; };
                "triple_press" = rec { type = "remote_button_triple_press"; subtype = type; };
                "quadruple_press" = rec { type = "remote_button_quadruple_press"; subtype = type; };
                "quintiple_press" = rec { type = "remote_button_quintiple_press"; subtype = type; };
                "long_press" = { type = "remote_button_long_press"; subtype = "button"; };
              };

              generateTriggers = friendlyName: ids:
                let
                  pressType = typeSubtypeMapping.${friendlyName}.type;
                  subtype = typeSubtypeMapping.${friendlyName}.subtype;
                in
                map
                  (id: {
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
              reading_light = "75849e0f307bbb353c0a78c9c206f5ce";

              party_light = "c086811938b0844e855bb43475c3c2fe";

              room_buttons = [ room_main_button bed_button couch_table_button ];
              kitchen_buttons = [ kitchen_main_button kitchen_table_button ];

              purifier = "c58ebba338d6c7cd8a1aca9007fb6e5d";
            in
            [
              (
                let
                  pressTypeMapping = {
                    "short_press" = kitchen_buttons;
                    "quadruple_press" = room_buttons;
                  };
                in
                {
                  alias = "kitchen lights toggle";
                  trigger = builtins.concatMap
                    (pressType: generateTriggers pressType pressTypeMapping.${pressType})
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
                }
              )
              (
                let
                  pressTypeMapping = {
                    "short_press" = room_buttons;
                    "quadruple_press" = kitchen_buttons;
                  };
                in
                {
                  alias = "room lights toggle";
                  trigger = builtins.concatMap
                    (pressType: generateTriggers pressType pressTypeMapping.${pressType})
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
                }
              )
              (
                let
                  pressTypeMapping = {
                    "double_press" = room_buttons;
                  };
                in
                {
                  alias = "room lights full brightness";
                  trigger = builtins.concatMap
                    (pressType: generateTriggers pressType pressTypeMapping.${pressType})
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
                }
              )
              (
                let
                  pressTypeMapping = {
                    "double_press" = kitchen_buttons;
                  };
                in
                {
                  alias = "kitchen lights full brightness";
                  trigger = builtins.concatMap
                    (pressType: generateTriggers pressType pressTypeMapping.${pressType})
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
                }
              )
              (
                let
                  pressTypeMapping = {
                    "long_press" = room_buttons;
                  };
                in
                {
                  alias = "reading light toggle";
                  trigger = builtins.concatMap
                    (pressType: generateTriggers pressType pressTypeMapping.${pressType})
                    (builtins.attrNames pressTypeMapping);
                  action = [
                    {
                      type = "toggle";
                      device_id = reading_light;
                      entity_id = "light.reading_light";
                      domain = "light";
                    }
                  ];
                }
              )
              (
                let
                  pressTypeMapping = {
                    "long_press" = kitchen_buttons;
                  };
                in
                {
                  alias = "party light toggle";
                  trigger = builtins.concatMap
                    (pressType: generateTriggers pressType pressTypeMapping.${pressType})
                    (builtins.attrNames pressTypeMapping);
                  action = [
                    {
                      type = "toggle";
                      device_id = party_light;
                      entity_id = "light.party_light";
                      domain = "light";
                    }
                  ];
                }
              )
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

          default_config = { };
        };
      };
      adguardhome = {
        enable = true;
        mutableSettings = false;
        # only affects the web interface port
        openFirewall = false;
        settings = {
          users = [{
            name = "glib";
            password = "$2y$05$y0ENgc6LYa.yRCgtTG9eneZJTimtnlGV6AaIFNbp71byq/Qtn6Oru";
          }];
          bind_port = frontendServices.adguard.port;
          bind_host = "127.0.0.1";
          dns = rec {
            bind_hosts = [ machineIpAddress ];
            filtering_enabled = true;
            blocked_response_ttl = 60 * 60 * 24;
            safe_search = {
              enabled = false;
            };
            ratelimit = 100;
            upstream_dns = [
              "1.1.1.1"
              "1.0.0.1"
              "[/${config.networking.domain}/]127.0.0.1:${builtins.toString dnsmasqPort}"
              "[/wpad.${config.networking.domain}/]#"
              "[/lb._dns-sd._udp.${config.networking.domain}/]#"
            ];
            bootstrap_dns = upstream_dns;
            all_servers = true;
            use_http3_upstreams = true;
            # 50 MBytes
            cache_size = 1024 * 1024 * 50;
          };
          dhcp = {
            enabled = false;
          };
          clients = {
            runtime_sources = {
              hosts = false;
            };
          };
        };
      };

    };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 53 67 ];

  system.stateVersion = "22.11";

}

