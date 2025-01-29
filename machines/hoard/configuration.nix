{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [./hardware-configuration.nix];

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
    wireless.enable = false;
    usePredictableInterfaceNames = true;
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
    groups.media = {};
    users = {
      gshpychka = {
        shell = pkgs.zsh;
        isNormalUser = true;
        extraGroups = ["wheel" "plugdev" "usb" "media"];
        packages = with pkgs; [neovim git];
        openssh.authorizedKeys.keys = [
          # eve
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB737o9Ltm1K3w9XX9SBHNW1JT4NpCPP5qg9R+SB18dG"
        ];
        initialHashedPassword = "";
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
    glances = {
      # remote system monitoring
      enable = true;
      openFirewall = true;
    };
    fstrim.enable = true;
    plex = {
      enable = true;
      openFirewall = true;
      group = "media";
    };
    deluge = {
      enable = true;
      declarative = true;
      group = "media";
      openFirewall = true;
      web = {
        enable = true;
        openFirewall = true;
        port = 8080;
      };
      authFile = builtins.toFile "auth" "localclient:deluge:10\n";
      config = {
        listen_ports = [6881 6891];
        allow_remote = true;
        pre_allocate_storage = true;
        download_location = "/mnt/torrents";
        torrentfiles_location = "/mnt/torrents";
        max_upload_speed = 0;
        new_release_check = false;
        max_active_limit = 50;
        max_active_downloading = 10;
        max_active_seeding = 0;
      };
    };
    avahi = {
      enable = true;
      nssmdns = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        hinfo = true;
        workstation = true;
        userServices = true;
      };
    };
  };

  programs = {
    ssh.startAgent = false;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    atop = {
      enable = true;
      setuidWrapper.enable = true;
    };
  };

  system.stateVersion = "24.11";
}
