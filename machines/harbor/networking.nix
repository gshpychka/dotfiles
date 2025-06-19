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
      enableSubdomains = true;
    }
    {
      name = "reaper";
      ip = "192.168.1.4";
      mac = "C8:7F:54:0B:FB:8C";
      enableSubdomains = true;
    }
    {
      name = "switch-alpha";
      ip = "192.168.1.5";
      mac = "98:BA:5F:46:87:00";
      enableSubdomains = false;
    }
    {
      name = "air-conditioner";
      ip = "192.168.1.51";
      mac = "08:BC:20:04:48:5A";
      enableSubdomains = false;
    }
    {
      name = "tv";
      ip = "192.168.1.52";
      mac = "1C:AF:4A:0C:6E:76";
      enableSubdomains = false;
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
    hosts =
      builtins.listToAttrs (
        map (h: {
          name = h.ip;
          value = [ h.name ];
        }) staticHosts
      )
      // {
        # override default /etc/hosts entry that maps our own domain to our LAN address
        # otherwise, it will map to 127.0.0.2
        # we insert our row at the bottom, so it will take precedence
        "${machineAddress}" = [ config.networking.hostName ];
      };

    firewall = {
      allowedTCPPorts = [
        53 # TCP fallback for large DNS responses (rare but needed for spec compliance)
        853 # DNS over TLS (DoT)
      ];
      allowedUDPPorts = [
        53 # DNS queries from clients
        67 # DHCP server→client (offers, acks)
      ];
    };
  };

  services.resolved.enable = lib.mkForce false; # disable systemd‑resolved stub

  # used by processes on this machine to find out how to resolve DNS
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.1 # libc resolver talks to AdGuard Home
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
          "127.0.0.1" # for local processes
          machineAddress # serve clients directly
        ];
        port = 53; # standard DNS port
        filtering_enabled = true;
        ratelimit = 100; # qps
        upstream_mode = "fastest_addr"; # single upstream, but keep for consistency
        upstream_dns = [
          # Forward all queries to dnsmasq
          "127.0.0.1#${toString config.services.dnsmasq.settings.port}"
        ];
        use_private_ptr_resolvers = true;
        local_ptr_upstreams = [
          "127.0.0.1#${toString config.services.dnsmasq.settings.port}"
        ];
        bootstrap_dns = [ ];
        allowed_clients = [
          "127.0.0.1/32" # localhost
          "192.168.1.0/24" # LAN clients
        ];
        aaaa_disabled = true;
        upstream_timeout = "1s";
        use_http3_upstreams = false; # not relevant for single local upstream
        enable_dnssec = false; # dnsmasq handles DNSSEC validation
        cache_size = 1024 * 1024 * 50;
        blocked_response_ttl = 60 * 60 * 24;

        # we don't want to use /etc/hosts, local domains should have been resolved by dnsmasq
        hostsfile_enabled = false;
      };
      tls = {
        enabled = true; # Enable DoT only
        server_name = "dns.${config.networking.fqdn}"; # Required for DDR and client validation
        port_dns_over_tls = 853;
        port_https = 0; # DoH disabled
        certificate_chain = "/var/lib/acme/${config.networking.fqdn}/fullchain.pem";
        private_key = "/var/lib/acme/${config.networking.fqdn}/key.pem";
      };
      filtering = {
        filtering_enabled = true;
        blocked_response_ttl = 60 * 60 * 24;
        safe_search = {
          enabled = false;
        };
      };
      clients = {
        # the only client is localhost anyway
        runtime_sources = {
          whois = false;
          arp = false;
          rdns = false;
          dhcp = false; # only works if adguard is the DHCP server
          hosts = true;
        };
      };
    };
  };
  services.dnsmasq = {
    enable = true;
    settings = {
      "listen-address" = [
        "127.0.0.1" # only listen locally for AdGuard Home forwarding
      ];
      port = 5353; # use non-standard port to avoid conflict with AdGuard Home
      domain = config.networking.domain; # authoritative local domain
      "expand-hosts" = true; # add domain to /etc/hosts names (local domain can be omitted)
      "localise-queries" = true; # prefer same‑subnet answers (if multiple are available)
      "stop-dns-rebind" = true; # Reject addresses from upstream nameservers which are in the private IP ranges
      "bogus-priv" = true; # drop RFC1918 reverse look‑ups that are not in DHCP leases
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
          # Apple Bonjour service discovery queries
          # like `b._dns-sd._udp.125.113.150.10.in-addr.arpa`
          # are not caught by bogus-priv
          # so we handle them more explicitly
          # RFC 1918
          "/10.in-addr.arpa/"
          "/168.192.in-addr.arpa/"
          # technically covers more than what the RFC does, but yolo
          "/172.in-addr.arpa/"

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
        (map (h: "/" + h.name + "." + config.networking.domain + "/" + h.ip) (
          # Filter out hosts that don't need subdomain resolution
          lib.filter (h: h ? enableSubdomains && h.enableSubdomains) staticHosts
        ))
        ++ [ "/${config.networking.hostName}.${config.networking.domain}/${machineAddress}" ]
      );

      # upstream DNS with DoT and DNSSEC
      server = [
        # Cloudflare DNS over TLS
        "tls://1.1.1.1#cloudflare-dns.com"
        "tls://1.0.0.1#cloudflare-dns.com"
        # Google DNS over TLS
        "tls://8.8.8.8#dns.google"
        "tls://8.8.4.4#dns.google"
        # Quad9 DNS over TLS
        "tls://9.9.9.9#dns.quad9.net"
        "tls://149.112.112.112#dns.quad9.net"
      ];
      "all-servers" = true; # query all servers, use fastest response
      "dnssec" = true;
      "trust-anchor" = [
        # Root zone DNSSEC trust anchor (KSK-2017)
        ". IN DS 20326 8 2 E06D44B80B8F1D39A95C0B0D7C65D08458E880409BBC683457104237C7F8EC8D"
      ];

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

  systemd.services.adguardhome = {
    requires = [ config.systemd.services.dnsmasq.name ]; # hard dependency on dnsmasq for local resolution
    after = [ config.systemd.services.dnsmasq.name ]; # start order - dnsmasq first
    serviceConfig.Restart = "on-failure";
  };
}
