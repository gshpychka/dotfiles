# Run services inside isolated network namespaces, each connected to the host
# through a veth pair. Responsibilities split by what owns each piece best:
#   - a oneshot service creates the veth pair and the namespace and configures
#     the namespace end. It tears any leftover state down to a clean slate
#     before creating things, so a crashed run cannot wedge startup, and it
#     creates the veth pair itself, so a restart never races device creation.
#   - systemd-networkd configures the host end: its address, and the policy rule
#     that selects an egress routing table. networkd owns the rule so its
#     foreign-rule cleanup never removes it.
#   - iptables provides NAT (SNAT for egress, DNAT for port forwards).
# NAT, addressing, and DNS are derived from the same typed options.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.my.netns;

  # Linux caps interface names at IFNAMSIZ (15 usable characters).
  ifnameMax = 15;

  # Healthcheck attempts spaced 0.1s apart, bounding the wait for the host end
  # at roughly 5s.
  healthcheckRetries = 50;

  cidr = address: prefix: "${address}/${toString prefix}";

  # Tear a namespace down to a clean slate. Deleting the namespace destroys the
  # veth pair with it; the explicit link delete covers a setup that failed
  # before the namespace existed. Every step tolerates absence, so the snippet
  # is safe to run before setup and again on stop.
  teardownScript = name: ns: ''
    ip netns delete ${name} 2>/dev/null || true
    ip link delete ${ns.hostInterface} 2>/dev/null || true
  '';

  setupScript = name: ns: ''
    set -euo pipefail

    # Start from a clean slate so a crashed previous run cannot wedge startup.
    ${teardownScript name ns}
    ip netns add ${name}

    # veth pair: one end stays on the host, the other moves into the namespace.
    # systemd-networkd addresses and brings up the host end once it appears.
    ip link add ${ns.hostInterface} type veth peer name ${ns.namespaceInterface}
    ip link set ${ns.namespaceInterface} netns ${name}

    # Namespace end, with the host as its default gateway.
    ip -n ${name} link set lo up
    ip -n ${name} address add ${cidr ns.namespaceAddress ns.prefixLength} dev ${ns.namespaceInterface}
    ip -n ${name} link set ${ns.namespaceInterface} up
    ip -n ${name} route add default via ${ns.hostAddress}
  '';

  # Confirm the namespace came up as configured before the unit reports started.
  # The host end and (for egress) the policy rule are configured by
  # systemd-networkd asynchronously, so those are polled within a bounded window.
  healthcheckScript = name: ns: ''
    set -euo pipefail

    [[ -e /run/netns/${name} ]] || {
      echo "netns ${name}: namespace is missing" >&2
      exit 1
    }
    [[ "$(ip -n ${name} -o addr show ${ns.namespaceInterface})" == *"${ns.namespaceAddress}/"* ]] || {
      echo "netns ${name}: ${ns.namespaceInterface} is missing address ${ns.namespaceAddress}" >&2
      exit 1
    }
    [[ "$(ip -n ${name} route show default)" == *"via ${ns.hostAddress} "* ]] || {
      echo "netns ${name}: default route is not via ${ns.hostAddress}" >&2
      exit 1
    }

    for ((i = 0; i < ${toString healthcheckRetries}; i++)); do
      if [[ "$(ip -o addr show dev ${ns.hostInterface} up 2>/dev/null)" == *"${ns.hostAddress}/"* ]]; then
        host_ready=true
      else
        host_ready=false
      fi
      ${
        if ns.egress != null then
          ''
            if [[ "$(ip rule show table ${toString ns.egress.routingTable} 2>/dev/null)" == *"from ${cidr ns.namespaceAddress 32}"* ]]; then
              rule_ready=true
            else
              rule_ready=false
            fi''
        else
          "rule_ready=true"
      }
      if $host_ready && $rule_ready; then
        exit 0
      fi
      sleep 0.1
    done

    echo "netns ${name}: systemd-networkd did not configure ${ns.hostInterface}${
      optionalString (ns.egress != null) " and the egress rule"
    } in time" >&2
    exit 1
  '';

  # iptables rules connecting a namespace to the outside world, modelled as
  # { table, spec } so each can be applied and deleted with the right table.
  natRules =
    ns:
    let
      nsCidr = cidr ns.namespaceAddress 32;
    in
    [
      {
        table = "filter";
        spec = "FORWARD -s ${nsCidr} -j ACCEPT";
      }
      {
        table = "filter";
        spec = "FORWARD -d ${nsCidr} -j ACCEPT";
      }
    ]
    ++ optional (ns.egress != null) {
      table = "nat";
      spec = "POSTROUTING -s ${nsCidr} -o ${ns.egress.interface} -j SNAT --to-source ${ns.egress.snatTo}";
    }
    ++ map (fwd: {
      table = "nat";
      spec = "PREROUTING -i ${fwd.interface} -p ${fwd.protocol} --dport ${toString fwd.port} -j DNAT --to-destination ${ns.namespaceAddress}:${toString fwd.port}";
    }) ns.portForwards;

  # Remove every existing copy of a rule before adding one back, so firewall
  # reloads (which re-run extraCommands) converge on a single copy even when an
  # earlier configuration left duplicates behind. The delete loop alone runs
  # from extraStopCommands.
  deleteRule = r: "while iptables -t ${r.table} -D ${r.spec} 2>/dev/null; do :; done\n";
  applyRule = r: "${deleteRule r}iptables -t ${r.table} -A ${r.spec}\n";

  netnsService = name: ns: {
    "${name}-netns" = {
      description = "Set up network namespace '${name}'";
      after = [
        "network.target"
        "systemd-networkd.service"
      ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.iproute2
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = setupScript name ns;
      postStart = healthcheckScript name ns;
      preStop = teardownScript name ns;
    };
  };

  # Bind a service into the namespace and tie its lifecycle to the setup unit,
  # so the service only ever runs once the namespace is in place and restarts
  # with it.
  boundService = name: ns: svc: {
    ${svc} = {
      after = [ "${name}-netns.service" ];
      bindsTo = [ "${name}-netns.service" ];
      partOf = [ "${name}-netns.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/${name}";
        BindReadOnlyPaths = optional (
          ns.nameservers != [ ]
        ) "/etc/netns/${name}/resolv.conf:/etc/resolv.conf";
      };
    };
  };

  # The host end of the veth pair, configured by systemd-networkd once the
  # service creates it: its address, and the policy rule routing traffic
  # sourced from the namespace via the egress table.
  hostNetwork = name: ns: {
    "40-netns-${name}" = {
      matchConfig.Name = ns.hostInterface;
      networkConfig.Address = cidr ns.hostAddress ns.prefixLength;
      # The namespace comes and goes; never let it hold up network-online.target.
      linkConfig.RequiredForOnline = "no";
      routingPolicyRules = optional (ns.egress != null) {
        From = cidr ns.namespaceAddress 32;
        Table = ns.egress.routingTable;
        Priority = ns.egress.rulePriority;
      };
    };
  };

  # /etc/resolv.conf for the namespace, bound over the file for bound services
  # (which enter via NetworkNamespacePath, bypassing the resolv.conf that
  # `ip netns exec` would supply).
  resolvConf =
    name: ns:
    optionalAttrs (ns.nameservers != [ ]) {
      "netns/${name}/resolv.conf".text = concatMapStrings (s: "nameserver ${s}\n") ns.nameservers;
    };

  namespaceAssertions = name: ns: [
    {
      assertion = config.systemd.network.enable;
      message = "my.netns.${name} requires systemd.network.enable; systemd-networkd configures the host end of the veth pair.";
    }
    {
      assertion = stringLength ns.hostInterface <= ifnameMax;
      message = "my.netns.${name}.hostInterface '${ns.hostInterface}' exceeds the ${toString ifnameMax}-character interface name limit.";
    }
    {
      assertion = stringLength ns.namespaceInterface <= ifnameMax;
      message = "my.netns.${name}.namespaceInterface '${ns.namespaceInterface}' exceeds the ${toString ifnameMax}-character interface name limit.";
    }
  ];

  # Map a function over every namespace. Call sites place this inside option
  # values, keeping the config's top-level keys static so the module system can
  # resolve this config's shape without recursing through config.my.netns.
  eachNamespace = f: mapAttrsToList f cfg;
in
{
  options.my.netns = mkOption {
    default = { };
    description = "Network namespaces, each connected to the host by a veth pair.";
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            hostAddress = mkOption {
              type = types.str;
              description = "IPv4 address of the host end of the veth pair.";
              example = "10.200.0.1";
            };

            namespaceAddress = mkOption {
              type = types.str;
              description = "IPv4 address of the namespace end of the veth pair. The host end is its default gateway.";
              example = "10.200.0.2";
            };

            prefixLength = mkOption {
              type = types.ints.between 0 32;
              default = 24;
              description = "Prefix length shared by both veth addresses.";
            };

            nameservers = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Nameservers for the namespace's resolv.conf, bound over /etc/resolv.conf for bound services.";
              example = [
                "1.1.1.1"
                "1.0.0.1"
              ];
            };

            hostInterface = mkOption {
              type = types.str;
              default = "${name}-host";
              defaultText = literalExpression ''"''${name}-host"'';
              description = "Name of the host end of the veth pair.";
            };

            namespaceInterface = mkOption {
              type = types.str;
              default = "${name}-ns";
              defaultText = literalExpression ''"''${name}-ns"'';
              description = "Name of the namespace end of the veth pair.";
            };

            egress = mkOption {
              default = null;
              description = "How the namespace reaches outside networks. Null leaves it isolated.";
              type = types.nullOr (
                types.submodule {
                  options = {
                    interface = mkOption {
                      type = types.str;
                      description = "Host interface the namespace's traffic leaves through, where SNAT is applied.";
                    };
                    snatTo = mkOption {
                      type = types.str;
                      description = "Source address the namespace's traffic is SNATed to.";
                    };
                    routingTable = mkOption {
                      type = types.int;
                      description = "Routing table the host uses for traffic sourced from the namespace.";
                    };
                    rulePriority = mkOption {
                      type = types.int;
                      default = 50;
                      description = "Priority of the routing policy rule that selects the egress table.";
                    };
                  };
                }
              );
            };

            portForwards = mkOption {
              default = [ ];
              description = "Host ports DNATed to the same port on the namespace address.";
              type = types.listOf (
                types.submodule {
                  options = {
                    interface = mkOption {
                      type = types.str;
                      description = "Host interface the forwarded traffic arrives on.";
                    };
                    protocol = mkOption {
                      type = types.enum [
                        "tcp"
                        "udp"
                      ];
                      default = "tcp";
                      description = "Transport protocol to forward.";
                    };
                    port = mkOption {
                      type = types.port;
                      description = "Port to forward.";
                    };
                  };
                }
              );
            };

            boundServices = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "systemd services to run inside this namespace.";
              example = [ "plex" ];
            };
          };
        }
      )
    );
  };

  config = {
    assertions = concatLists (eachNamespace namespaceAssertions);

    # Forwarding between the host and a namespace, and into it for port
    # forwards, both depend on IPv4 forwarding.
    boot.kernel.sysctl."net.ipv4.ip_forward" = mkIf (any (
      ns: ns.egress != null || ns.portForwards != [ ]
    ) (attrValues cfg)) (mkDefault 1);

    systemd.services = mkMerge (
      eachNamespace (
        name: ns: mkMerge ([ (netnsService name ns) ] ++ map (boundService name ns) ns.boundServices)
      )
    );

    systemd.network.networks = mkMerge (eachNamespace hostNetwork);

    environment.etc = mkMerge (eachNamespace resolvConf);

    networking.firewall.extraCommands = concatStrings (
      eachNamespace (name: ns: concatMapStrings applyRule (natRules ns))
    );
    networking.firewall.extraStopCommands = concatStrings (
      eachNamespace (name: ns: concatMapStrings deleteRule (natRules ns))
    );
  };
}
