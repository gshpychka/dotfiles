{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
  ];

  boot = {
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "usbhid"
        "usb_storage"
      ];
    };
    kernelPackages = pkgs.linuxKernel.packages.linux_rpi4;
    loader = {
      grub.enable = false;
      # Enables the generation of /boot/extlinux/extlinux.conf
      generic-extlinux-compatible.enable = true;
    };
  };

  my.user = "pi";

  networking = {
    hostName = "harbor";
  };

  my.tailscale = {
    enable = true;
    ssh = true;
    magicDns = false;
    exitNode = true;
  };

  users = {
    users = {
      ${config.my.user} = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        packages = with pkgs; [
          neovim
        ];
        openssh.authorizedKeys.keys = [
          config.my.sshKeys.main
        ];
        initialHashedPassword = "";
      };
    };
  };
  nixpkgs.config.permittedInsecurePackages = [ "openssl-1.1.1w" ];

  nix.settings = {
    auto-optimise-store = true;
  };
  nix.gc = {
    dates = "weekly";
    automatic = true;
    options = "--delete-older-than 7d";
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
    domain = config.my.domain;
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

  };

  networking.firewall.allowedTCPPorts = [
    config.services.nginx.defaultSSLListenPort
  ];

  system.stateVersion = "22.11";
}
