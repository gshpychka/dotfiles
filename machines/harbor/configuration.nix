{ config, pkgs, ... }:

let
  machineIpAddress = "192.168.1.2";
  networkInterface = "eth0";
  routerIpAddress = "192.168.1.1";
  dnsmasqPort = 5353;
  sharedVars = import ./variables.nix;
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
    hostName = sharedVars.harborHost;
    defaultGateway = routerIpAddress;
    domain = localDomain;
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

  users.users.${sharedVars.harborUsername} = {
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
      ports = [ sharedVars.harborSshPort ];
    };
    dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        interface = networkInterface;
        domain = sharedVars.localDomain;
        local = "/${sharedVars.localDomain}/";
        no-resolv = true;
        no-hosts = true;
        listen-address = "127.0.0.1";
        port = dnsmasqPort;
        address = [
          "/${hostName}.${sharedVars.localDomain}/${machineIpAddress}"
        ];
        dhcp-range = "${networkInterface},192.168.1.3,192.168.1.254,24h";
        dhcp-option = [
          "option:router,${routerIpAddress}"
          "option:domain-name,${sharedVars.localDomain}"
          "option:dns-server,${machineIpAddress}"
        ];
        dhcp-host = [
          "00:17:88:A4:FF:6B,hue,192.168.1.131"
          "5C:E5:0C:AD:6A:7B,party-light,192.168.1.153"
        ];
      };
    };

    plex = {
      enable = true;
      openFirewall = true;
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
          legacy_api = false;
          legacy_availability_payload = false;
        };
        device_options.legacy = false;
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
      openFirewall = false;
    };
    adguardhome = {
      enable = true;
      mutableSettings = false;
      # only affects the web interface port
      openFirewall = false;
      settings = {
        bind_port = 2999;
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
            "[/${sharedVars.localDomain}/]127.0.0.1:${builtins.toString dnsmasqPort}"
            "[/wpad.${sharedVars.localDomain}/]#"
            "[/lb._dns-sd._udp.${sharedVars.localDomain}/]#"
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
  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.allowedUDPPorts = [ 53 67 ];

  system.stateVersion = "22.11";

}

