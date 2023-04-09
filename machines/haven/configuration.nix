{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  networking.hostName = "haven";
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  time.timeZone = "Europe/Kiev";

  users.users.pi = {
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

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    ports = [ 420 ];
  };

  virtualisation = {

    podman = {
      enable = true;
      dockerCompat = true;
    };

    oci-containers = {
      backend = "podman";
      containers = {
        mosquitto = {
          image = "eclipse-mosquitto:2.0";
          ports = [ "1883:1883" "9001:9001" ];
          cmd = [ "mosquitto" "-c" "/mosquitto-no-auth.conf" ];
        };
        zigbee2mqtt = {
          image = "koenkk/zigbee2mqtt";
          dependsOn = [ "mosquitto" ];
          ports = [ "8080:8080" ];
          environment = {
            TZ = "Europe/Kiev";
          };
          volumes = [ "${toString ./zigbee2mqtt}:/app/data" "/run/udev:/run/udev:ro" ];
          extraOptions = [ "--device=/dev/ttyACM0:/dev/ttyACM0" ];
        };
      };
    };
  };


  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8080 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  system.stateVersion = "22.11";

}

