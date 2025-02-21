{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [./hardware-configuration.nix ../../modules/qbittorrent.nix];

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
    groups.media = {members = ["plex"];};
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
      "time-machine" = {
        group = "media";
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
        "time-machine" = {
          "path" = "/mnt/hoard/shares/time-machine";
          "valid users" = "time-machine";
          "public" = "no";
          "writeable" = "yes";
          "force user" = "time-machine";
          "fruit:aapl" = "yes";
          "fruit:time machine" = "yes";
          "vfs objects" = "catia fruit streams_xattr";
        };
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
    qbittorrent = {
      enable = true;
      openFirewall = true;
      group = "media";
    };
    prowlarr = {
      enable = true;
      openFirewall = true;
    };
    sonarr = {
      enable = true;
      openFirewall = true;
      group = "media";
    };
    radarr = {
      enable = true;
      openFirewall = true;
      group = "media";
    };
  };

  programs = {
    ssh.startAgent = false;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  system.stateVersion = "24.11";
}
