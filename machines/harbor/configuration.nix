{
  config,
  pkgs,
  ...
}:
let
  machineIpAddress = "192.168.1.2";
  networkInterface = "eth0";
  routerIpAddress = "192.168.1.1";
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/acme.nix
  ];

  boot = {
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "usbhid"
        "usb_storage"
      ];
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
    hostName = "harbor";
    defaultGateway = routerIpAddress;
    useDHCP = false;
    nameservers = [ "127.0.0.1" ];
    enableIPv6 = false;
    interfaces.${networkInterface}.ipv4 = {
      addresses = [
        {
          address = machineIpAddress;
          prefixLength = 24;
        }
      ];
    };
  };

  time.timeZone = "Europe/Kyiv";

  hardware = {
    bluetooth.enable = true;
  };

  users = {
    users = {
      pi = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        packages = with pkgs; [
          neovim
          git
        ];
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
    enableGlobalCompInit = false;
    enableLsColors = false;
  };

  security = {
    sudo.enable = true;
    pam = {
      sshAgentAuth.enable = true;
      services.sudo.sshAgentAuth = true;
    };
  };

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  my.acme = {
    enable = true;
    extraDomainNames = [ "*.${config.networking.fqdn}" ];
  };

  services = {
    # argononed fails to start
    # hardware.argonone.enable = true;
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
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts = {
        adguard = {
          serverName = "adguard.${config.networking.fqdn}";
          useACMEHost = config.networking.fqdn;
          onlySSL = true;
          extraConfig = ''
            proxy_buffering off;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.adguardhome.port}";
          };
        };
        "block-root-domain" = {
          serverName = config.networking.fqdn; # Explicitly block the base domain
          useACMEHost = config.networking.fqdn;
          onlySSL = true;
          default = true;
          locations."/" = {
            return = "444";
          };
        };
      };
    };
    adguardhome = {
      enable = true;
      mutableSettings = false;
      host = "127.0.0.1";
      settings = {
        schema_version = 29;
        users = [
          {
            name = "glib";
            password = "$2y$05$y0ENgc6LYa.yRCgtTG9eneZJTimtnlGV6AaIFNbp71byq/Qtn6Oru";
          }
        ];
        theme = "dark";
        auth_attempts = 5;
        block_auth_min = 15;
        dns = {
          bind_hosts = [
            machineIpAddress
            "127.0.0.1"
          ];
          ratelimit = 0;
          upstream_dns = [
            "tls://1dot1dot1dot1.cloudflare-dns.com"
          ];
          allowed_clients = [
            "${routerIpAddress}/24"
            "127.0.0.1/32"
          ];
          bootstrap_dns = [
            "1.1.1.1"
            "1.0.0.1"
          ];
          aaaa_disabled = true;
          upstream_timeout = "1s";
          use_http3_upstreams = true;
          enable_dnssec = true;
          # 50 MBytes
          cache_size = 1024 * 1024 * 50;
          hostsfile_enabled = false;
        };
        filtering = {
          filtering_enabled = true;
          blocked_response_ttl = 60 * 60 * 24;
          safe_search = {
            enabled = false;
          };
          rewrites = [
            {
              domain = config.networking.fqdn;
              # otherwise it resolves to 127.0.0.2
              answer = machineIpAddress;
            }
            {
              domain = "*.${config.networking.fqdn}";
              answer = machineIpAddress;
            }
            {
              # TODO: need to set up a real DNS server on harbor to handle
              # local queries instead of using rewrites like this
              domain = "*.reaper.${config.networking.domain}";
              answer = "192.168.1.20";
            }
            {
              domain = "*.hoard.${config.networking.domain}";
              answer = "192.168.1.59";
            }
            {
              domain = "router.${config.networking.domain}";
              answer = routerIpAddress;
            }
          ];
        };
        # dhcp = {
        #   enabled = true;
        #   interface_name = networkInterface;
        #   dhcpv4 = {
        #     gateway_ip = routerIpAddress;
        #     subnet_mask = "255.255.255.0";
        #     range_start = "192.168.1.3";
        #     range_end = "192.168.1.254";
        #   };
        # };
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    config.services.nginx.defaultSSLListenPort
    config.services.nginx.defaultHTTPListenPort
  ];
  networking.firewall.allowedUDPPorts = [
    53
    67
  ];

  system.stateVersion = "22.11";
}
