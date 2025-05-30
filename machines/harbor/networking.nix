{
  config,
  lib,
  ...
}:

let
  lanInterface = "eth0";
  routerAddress = "192.168.1.1";
  machineAddress = "192.168.1.2";

  # Hosts that need wildcard sub-domains (e.g. foo.reaper.lan → reaper’s IP)
  staticHosts = [
    {
      name = "hoard";
      ip = "192.168.1.3";
      mac = "E8:FF:1E:D6:89:EB";
    }
    {
      name = "reaper";
      ip = "192.168.1.4";
      mac = "C8:7F:54:0B:FB:8C";
    }
  ];

in
{
  networking = {
    interfaces."${lanInterface}" = {
      useDHCP = false; # we are the only DHCP server
      ipv4.addresses = [
        {
          address = machineAddress;
          prefixLength = 24;
        }
      ];
    };

    defaultGateway = routerAddress;
    enableIPv6 = false;
    nameservers = [ "127.0.0.1" ];
    # Build /etc/hosts so expand‑hosts can append the domain and local look‑ups work offline
    hosts = builtins.listToAttrs (
      map (h: {
        name = h.ip;
        value = [ h.name ];
      }) staticHosts
    );

    firewall = {
      allowedTCPPorts = [
        53 # large DNS replies and DNSSEC
      ];
      allowedUDPPorts = [
        53 # normal DNS
        67 # DHCP server→client
        68 # DHCP client→server
      ];
    };
  };

  services.resolved.enable = lib.mkForce false; # disable systemd‑resolved stub

  # /etc/resolv.conf is not used, but we still set it just in case something uses it as a fallback
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.1 # libc resolver talks to dnsmasq
    search ${config.networking.domain} # bare hostnames auto‑expand
  '';

  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    host = "127.0.0.1"; # for the web UI
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
          "127.0.0.1"
        ];
        port = 5353; # does not clash with dnsmasq
        filtering_enabled = true;
        ratelimit = 100; # qps
        upstream_mode = "parallel";
        upstream_dns = [
          "tls://1dot1dot1dot1.cloudflare-dns.com"
          "tls://dns.google"
          "tls://dns.quad9.net"
        ];
        allowed_clients = [
          # kind of redundant given our bind_hosts and firewall, but doesn't hurt
          "127.0.0.1/32"
        ];
        bootstrap_dns = [
          "1.1.1.1"
          "8.8.8.8"
          "9.9.9.9"
        ];
        aaaa_disabled = true;
        upstream_timeout = "1s";
        use_http3_upstreams = true;
        enable_dnssec = true;
        cache_size = 1024 * 1024 * 50;
        blocked_response_ttl = 60 * 60 * 24;

        # we don't want to use /etc/hosts, local domains should have been resolved by dnsmasq
        hostsfile_enabled = false;
      };
      filtering = {
        filtering_enabled = true;
        blocked_response_ttl = 60 * 60 * 24;
        safe_search = {
          enabled = false;
        };
      };
    };
  };
  services.dnsmasq = {
    enable = true;
    settings = {
      interface = lanInterface;
      domain = config.networking.domain; # authoritative local domain
      "expand-hosts" = true; # add domain to /etc/hosts names (local domain can be omitted)
      "localise-queries" = true; # prefer same‑subnet answers
      "bogus-priv" = true; # drop RFC1918 reverse look‑ups
      "no-resolv" = true; # ignore /etc/resolv.conf

      # resolve these locally
      local = (
        # Set our static hosts to be resolved locally.
        # We could have set the entire `${config.networking.domain}` zone to be local, but then we wouldn't be able
        # to use a public domain name for other use-cases (have it be resolved upstream)
        # So we explicitly list all the hosts here, and all other subdomains will be forwarded upstream.
        (map (h: "/" + h.name + "." + config.networking.domain + "/") staticHosts)
        ++ [
          # reverse zone kept local
          "/1.168.192.in-addr.arpa/"

          # suppress WPAD queries
          "/wpad.${config.networking.domain}/"
          "/wpad/"
        ]
      );

      # wildcard A records for all our static hosts
      # allows us to use subdomains
      # dnsmasq cannot alias wildcard to another name, so we have to specify the IPs
      # this is why we use static leases at all
      address = (
        (map (h: "/" + h.name + "." + config.networking.domain + "/" + h.ip) staticHosts)
        ++ [ "/${config.networking.hostName}.${config.networking.domain}/${machineAddress}" ]
      );

      # upstream
      server = [ "127.0.0.1#${toString config.services.adguardhome.settings.dns.port}" ];

      "dhcp-authoritative" = true; # tell clients we are the the only DHCP server
      "dhcp-range" = "192.168.1.100,192.168.1.254,24h";
      "dhcp-option" = [
        "option:router,${routerAddress}"
        "option:dns-server,${machineAddress}"
        "option:domain-search,${config.networking.domain}"
      ];
      # sticky leases
      "dhcp-host" = (map (h: "${h.mac},${h.ip},${h.name}") staticHosts);

    };
  };

  systemd.services.dnsmasq = {
    requires = [ config.systemd.services.adguardhome.name ]; # hard dependency
    after = [ config.systemd.services.adguardhome.name ]; # start order
    serviceConfig.Restart = "on-failure";
  };
}
