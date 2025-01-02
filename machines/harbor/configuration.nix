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

  p1sIpAddress = "192.168.1.159";
  camIpAddress = "192.168.1.146";
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
    users = {
      ${config.shared.harborUsername} = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = ["wheel"];
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
      adguard = {
        subdomain = "adguard";
        port = 3000;
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
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [80];
  networking.firewall.allowedUDPPorts = [53 67];

  system.stateVersion = "22.11";
}
