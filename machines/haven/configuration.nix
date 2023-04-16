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
  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
      ports = [ 420 ];
    };
    mosquitto = {
      enable = true;
      logType = [ "all" ];
      logDest = [ "stdout" ];
      persistence = false;
      listeners = [
        {
          address = "127.0.0.1";
          port = 1776;
          # TODO: add auth
          omitPasswordAuth = true;
          users = { };
          settings = { allow_anonymous = true; };
          # TODO: least privilege
          acl = [ "topic readwrite #" "pattern readwrite #" ];
        }
      ];
    };
    zigbee2mqtt = {
      enable = true;
      settings = {
        permit_join = false;
        mqtt = {
          base_topic = "zigbee2mqtt";
          server = "mqtt://127.0.0.1:1776";
        };
        serial.port = "/dev/ttyACM0";
        frontend.port = 8080;
        advanced = {
          # TODO: encrypt and change
          network_key = [ 20 190 55 88 82 34 150 92 237 74 167 132 123 219 110 39 ];
          legacy_api = false;
          legacy_availability_payload = false;
        };
        device_options.legacy = false;
        devices = {
          "0x00158d0004033fa5" = {
            friendly_name = "extra_button_0";
          };
          "0x00158d0003d4d818" = {
            friendly_name = "room_main_switch";
          };
          "0x00158d0004254a53" = {
            friendly_name = "kitchen_main_switch";
          };
          "0x00158d0003d18bbf" = {
            friendly_name = "bed_button";
          };
          "0x00158d000403d816" = {
            friendly_name = "couch_table_button";
          };
          "0x00158d0004238a73" = {
            friendly_name = "kitchen_table_button";
          };
        };
      };
    };
    node-red = {
      enable = true;
      # TODO: include nodes here
      package = pkgs.nodePackages_latest.node-red.override {
        extraNodePackages = [ ];
      };
      # TODO: declarative configuration of nodes and flows
      withNpmAndGcc = true;
      openFirewall = true;
    };
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  system.stateVersion = "22.11";

}

