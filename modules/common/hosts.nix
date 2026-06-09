{ lib, ... }:
# Fleet registry: the single source of truth for the LAN layout and per-host
# SSH access data. Consumed by harbor's dnsmasq/DHCP setup
# (machines/harbor/networking.nix) and the SSH client config
# (modules/home-manager/ssh.nix).
{
  options.my = {
    lan = {
      cidr = lib.mkOption {
        type = lib.types.str;
        description = "LAN subnet in CIDR notation";
      };
      routerIp = lib.mkOption {
        type = lib.types.str;
        description = "LAN router/gateway address";
      };
    };
    hosts = lib.mkOption {
      description = "Known hosts: LAN addressing and SSH access data";
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            lanIp = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Static LAN address (null = dynamic or not on the LAN)";
            };
            mac = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "MAC address for the DHCP static lease (null = host assigns its own address)";
            };
            enableSubdomains = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Resolve wildcard *.<name>.<domain> to lanIp";
            };
            sshUser = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "SSH user (null = my.user via the catch-all local match block)";
            };
            sshSettings = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              description = "Extra ssh_config keys merged into this host's Match block";
            };
          };
        }
      );
    };
  };

  config.my = {
    lan = {
      cidr = "192.168.1.0/24";
      routerIp = "192.168.1.1";
    };
    hosts = {
      # harbor is the DHCP server and assigns its own static address (no lease)
      harbor = {
        lanIp = "192.168.1.2";
        enableSubdomains = true;
        # harbor's main user is "pi" (see machines/harbor/default.nix), not my.user
        sshUser = "pi";
      };
      hoard = {
        lanIp = "192.168.1.3";
        mac = "E8:FF:1E:D6:89:EB";
        enableSubdomains = true;
      };
      reaper = {
        lanIp = "192.168.1.4";
        mac = "C8:7F:54:0B:FB:8C";
        enableSubdomains = true;
      };
      switch-alpha = {
        lanIp = "192.168.1.5";
        mac = "98:BA:5F:46:87:00";
      };
      air-conditioner = {
        lanIp = "192.168.1.51";
        mac = "08:BC:20:04:48:5A";
      };
      tv = {
        lanIp = "192.168.1.52";
        mac = "1C:AF:4A:0C:6E:76";
      };
      p1s = {
        lanIp = "192.168.1.53";
        mac = "EC:DA:3B:99:80:E4";
      };

      # ssh-only entries (not on the LAN / no static lease)
      iso = {
        sshUser = "nixos";
      };
      kodi = {
        sshUser = "root";
        sshSettings = {
          ForwardAgent = false;
          SetEnv.TERM = "xterm-256color";
        };
      };
    };
  };
}
