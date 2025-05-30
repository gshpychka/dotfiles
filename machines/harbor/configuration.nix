{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/acme.nix
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

  networking = {
    hostName = "harbor";
  };

  time.timeZone = "Europe/Kyiv";

  users = {
    users = {
      pi = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        packages = with pkgs; [
          neovim
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

  };

  networking.firewall.allowedTCPPorts = [
    config.services.nginx.defaultSSLListenPort
  ];

  system.stateVersion = "22.11";
}
