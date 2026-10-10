# SPIRE issuer: the off-the-shelf counterpart of machines/reaper/oidc-issuer.
# SPIRE (https://spiffe.io) signs short-lived JWT-SVIDs that AWS STS trusts
# through a custom IAM OIDC provider at https://spire.glib.sh, the same way it
# trusts GitHub Actions' tokens. Everything runs on reaper:
#
# - spire-server: the CA and token signer, on loopback only. Its JWT signing
#   key rotates on its own and is published in the JWKS days before it
#   signs anything (ca_ttl below). The disk key manager keeps keys in
#   /var/lib/spire/server/keys.json, readable by the server alone but
#   unencrypted at rest; rotation bounds what a stolen key is worth.
# - spire-agent: proves to the server that it runs on reaper with reaper's TPM
#   (the EK public key hash; no PCRs, so firmware and boot changes don't
#   matter), and identifies callers of its Workload API socket by Unix user
#   and systemd unit.
# - oidc-discovery-provider: serves the discovery document and live JWKS on
#   a Unix socket. machines/reaper/cloudflare-tunnel.nix publishes those two
#   paths.
# - spire-entries: makes the server's registration entries (which caller gets
#   which identity) match my.spire.{users,services}, deleting any other entry.
# - spiffe-helper (user service): keeps a fresh token for AWS at
#   $XDG_RUNTIME_DIR/spiffe/aws.jwt for every user in my.spire.users.
#
# Bootstrap, from eve:
#   ssh reaper sudo nix shell nixpkgs#spire-tpm-plugin -c get_tpm_pubhash   # -> my.spire.tpmEkHash
#   cd infra && nix develop ..#infra; cd reaper && tg apply   # reaper-tunnel, spire DNS record
#   sops exec-file --no-fifo secrets/common/cloudflare-cert.pem 'env TUNNEL_ORIGIN_CERT={} cloudflared tunnel token --cred-file creds.json reaper-tunnel'
#   encrypt creds.json into secrets/reaper/cloudflare-tunnel.json, set my.spire.enable, deploy reaper
#
# AWS side, once per account:
#   aws iam create-open-id-connect-provider --url https://spire.glib.sh --client-id-list sts.amazonaws.com
#   each role's trust policy: Principal.Federated = that provider's ARN,
#   Action = sts:AssumeRoleWithWebIdentity, Condition.StringEquals =
#   { "spire.glib.sh:aud": "sts.amazonaws.com", "spire.glib.sh:sub": "spiffe://glib.sh/reaper/user/<user>" }
#
# Usage, as a user in my.spire.users:
#   spire-agent api fetch jwt -audience sts.amazonaws.com   # inspect a token
#   ~/.aws/config, which AWS CLIs and SDKs re-read whenever credentials expire:
#     [profile <name>]
#     role_arn = <role ARN>
#     web_identity_token_file = /run/user/<uid>/spiffe/aws.jwt
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.spire;
  server = config.services.spire.server;
  agent = config.services.spire.agent;
  inherit (config.networking) hostName;

  trustDomain = config.my.domain;
  spiffeId = path: "spiffe://${trustDomain}/${path}";
  # SPIRE's own ID; node entries hang off it
  serverId = spiffeId "spire/server";
  nodeId = spiffeId "node/${hostName}";
  userId = user: spiffeId "${hostName}/user/${user}";
  serviceId = unit: spiffeId "${hostName}/service/${unit}";

  audience = "sts.amazonaws.com";
  serverPort = 8081;
  # Root-owned: in the agent's own state directory the agent could plant a
  # symlink there for the root ExecStartPre to write and chown through.
  bootstrapBundle = "/run/spire-agent-bootstrap/bundle.pem";
  awsTokenFile = "aws.jwt";

  # IDs of the entries spire-entries writes, to tell them apart from SPIRE's own
  entryPrefix = "nix-";
  # The only characters a SPIFFE ID path segment and an entry ID both allow
  # (https://github.com/spiffe/spiffe/blob/main/standards/SPIFFE-ID.md#22-path).
  # User and unit names become both, so e.g. a template instance's "@" is out.
  validName = name: builtins.match "[A-Za-z0-9._-]+" name != null;
  selector = type: value: { inherit type value; };
  entries = [
    {
      # every agent attested with reaper's TPM gets the stable alias nodeId
      entry_id = "${entryPrefix}node-${hostName}";
      parent_id = serverId;
      spiffe_id = nodeId;
      selectors = [ (selector "tpm" "pub_hash:${cfg.tpmEkHash}") ];
    }
  ]
  ++ map (user: {
    entry_id = "${entryPrefix}user-${user}";
    parent_id = nodeId;
    spiffe_id = userId user;
    selectors = [ (selector "unix" "user:${user}") ];
  }) cfg.users
  ++ lib.mapAttrsToList (unit: service: {
    entry_id = "${entryPrefix}service-${unit}";
    parent_id = nodeId;
    spiffe_id = serviceId unit;
    selectors = [
      (selector "systemd" "id:${unit}.service")
      (selector "unix" "user:${service.user}")
    ];
  }) cfg.services;
  # the `spire-server entry create|update -data` format
  entriesFile = pkgs.writeText "spire-entries.json" (builtins.toJSON { inherit entries; });

  # SPIRE has no readiness notification, so dependents poll its healthcheck.
  # Bounded, so a broken server fails them (systemd retries) instead of
  # holding up boot: multi-user.target waits for their start jobs.
  waitForServer = pkgs.writeShellScript "spire-wait-for-server" ''
    export SPIRE_SERVER_PRIVATE_SOCKET=${server.settings.server.socket_path}
    for _ in $(seq 30); do
      ${lib.getExe' server.package "spire-server"} healthcheck >/dev/null 2>&1 && exit 0
      sleep 1
    done
    echo "spire-server is not healthy" >&2
    exit 1
  '';

  reconcileEntries = pkgs.writeShellApplication {
    name = "spire-entries";
    runtimeInputs = [
      server.package
      pkgs.jq
    ];
    # $have and $present are jq variables, single-quoted on purpose
    excludeShellChecks = [ "SC2016" ];
    text = ''
      export SPIRE_SERVER_PRIVATE_SOCKET=${server.settings.server.socket_path}
      ${waitForServer}

      # Every entry on the server is managed here: one not in my.spire is
      # deleted, so a mapping added by hand, or by someone with one-off admin
      # access, does not survive the next start. Deletions go first, so a
      # failing create cannot hold up a revocation.
      have=$(spire-server entry show -output json | jq -c '[.entries[]?.id]')
      want=$(jq -c '[.entries[].entry_id]' ${entriesFile})
      jq -r --argjson want "$want" '.[] | select(IN($want[]) | not)' <<<"$have" \
        | while read -r stale; do spire-server entry delete -entryID "$stale"; done

      # the wanted entries the server does (true) or does not (false) have yet
      wanted() {
        jq --argjson have "$have" --argjson present "$1" \
          '{entries: [.entries[] | select((.entry_id | IN($have[])) == $present)]}' ${entriesFile}
      }

      created=$(wanted false)
      if [ "$(jq '.entries | length' <<<"$created")" -gt 0 ]; then
        spire-server entry create -data - <<<"$created"
      fi
      updated=$(wanted true)
      if [ "$(jq '.entries | length' <<<"$updated")" -gt 0 ]; then
        spire-server entry update -data - <<<"$updated"
      fi
    '';
  };

  discoveryUnit = "spire-oidc-discovery-provider";
  # In the provider's own runtime directory. Nobody else can create a file
  # there, so nothing can stand in for the provider while it is down, as any
  # local user could on a free loopback port.
  discoverySocket = "/run/${discoveryUnit}/discovery.sock";
  discoveryConfig = (pkgs.formats.hcl1 { }).generate "oidc-discovery-provider.conf" {
    domains = [ cfg.issuerHost ];
    jwt_issuer = cfg.issuerUrl;
    # the provider makes it world-connectable; it serves only public keys
    listen_socket_path = discoverySocket;
    # AWS ignores it; it makes the published keys' purpose explicit
    set_key_use = true;
    workload_api = {
      inherit (agent.settings.agent) socket_path;
      trust_domain = trustDomain;
    };
  };

  helperConfig = pkgs.writeText "spiffe-helper-aws.conf" ''
    agent_address = "${agent.settings.agent.socket_path}"
    daemon_mode = true
    # relative to WorkingDirectory, the user's $XDG_RUNTIME_DIR/spiffe
    cert_dir = "."
    jwt_svids = [{jwt_audience = "${audience}", jwt_svid_file_name = "${awsTokenFile}"}]
  '';

  # Sandboxing shared by the SPIRE daemons. Not ProtectProc=invisible: the
  # agent's unix attestor reads callers' /proc entries.
  hardening = {
    CapabilityBoundingSet = "";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
    IPAddressAllow = "localhost";
    IPAddressDeny = "any";
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
    ];
    # deny with an error, not SIGSYS: Go runtimes probe optional syscalls
    SystemCallErrorNumber = "EPERM";
  };
in
{
  options.my.spire = {
    enable = lib.mkEnableOption "the SPIRE-based OIDC issuer";
    issuerHost = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      # infra/reaper/dns.tf points this name at reaper-tunnel
      default = "spire.${config.my.domain}";
      description = "Public hostname of the issuer.";
    };
    issuerUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "https://${cfg.issuerHost}";
      description = "`iss` claim of every token; the provider URL AWS is configured with.";
    };
    discovery = {
      socket = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = discoverySocket;
        description = "Unix socket the discovery provider serves HTTP on, for the tunnel.";
      };
      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        # fixed by oidc-discovery-provider
        default = [
          "/.well-known/openid-configuration"
          "/keys"
        ];
        description = "The only paths the discovery provider serves.";
      };
    };
    tpmEkHash = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Hash of reaper's TPM endorsement key, printed by `get_tpm_pubhash`
        (spire-tpm-plugin). The server attests only an agent holding this TPM.
      '';
    };
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Users that get the identity spiffe://<domain>/<host>/user/<user>, for
        any of their processes, and a fresh AWS token from spiffe-helper.
      '';
    };
    services = lib.mkOption {
      default = { };
      description = ''
        System services, keyed by unit name without ".service", that get the
        identity spiffe://<domain>/<host>/service/<unit> when running as `user`.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.user = lib.mkOption {
            type = lib.types.str;
            description = "User the service runs as.";
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.tpmEkHash != null;
        message = "my.spire.tpmEkHash is required: run `get_tpm_pubhash` on ${hostName}.";
      }
      {
        assertion = lib.all (user: config.users.users ? ${user}) (
          cfg.users ++ lib.mapAttrsToList (_: service: service.user) cfg.services
        );
        message = "my.spire.users and my.spire.services.*.user must name users.users entries.";
      }
      {
        assertion = lib.all validName (cfg.users ++ lib.attrNames cfg.services);
        message = "my.spire.users and my.spire.services names may only contain [A-Za-z0-9._-]: they become SPIFFE ID path segments.";
      }
    ];

    # the CLIs find the sockets without -socketPath
    environment.variables = {
      SPIRE_SERVER_PRIVATE_SOCKET = server.settings.server.socket_path;
      SPIRE_AGENT_PUBLIC_SOCKET = agent.settings.agent.socket_path;
    };
    environment.systemPackages = [ pkgs.spire-tpm-plugin ];

    services.spire.server = {
      enable = true;
      settings = {
        server = {
          trust_domain = trustDomain;
          bind_address = "127.0.0.1";
          bind_port = serverPort;
          jwt_issuer = cfg.issuerUrl;
          # A JWT key signs for at most ca_ttl, which bounds a stolen key. Its
          # successor is published at min(ca_ttl/2, 30d) and signs from
          # min(ca_ttl/6, 7d) before expiry: 56h in which AWS can fetch it.
          # After reaper is off for longer, the server starts with a fresh key
          # AWS may need a few minutes to fetch, and the agent re-attests with
          # the TPM and the bundle ExecStartPre refreshes.
          ca_ttl = "168h";
          agent_ttl = "24h";
          default_x509_svid_ttl = "1h";
          default_jwt_svid_ttl = "5m";
          # JWT-SVID issuance is otherwise logged at debug level only
          audit_log_enabled = true;
        };
        plugins = {
          KeyManager.disk.plugin_data.keys_path = "$STATE_DIRECTORY/keys.json";
          DataStore.sql.plugin_data = {
            database_type = "sqlite3";
            connection_string = "$STATE_DIRECTORY/datastore.sqlite3";
          };
          NodeAttestor.tpm.plugin_data.hash_path = toString (
            pkgs.runCommand "spire-tpm-ek-hashes" { } ''
              mkdir $out
              touch $out/${cfg.tpmEkHash}
            ''
          );
        };
      };
    };
    systemd.services.spire-server.serviceConfig = hardening // {
      PrivateDevices = true;
      RestartSec = 5;
    };

    services.spire.agent = {
      enable = true;
      settings = {
        agent = {
          trust_domain = trustDomain;
          server_address = "127.0.0.1";
          server_port = serverPort;
          # Written fresh from the server at every start (ExecStartPre below),
          # so a re-bootstrap after a CA rollover always trusts the current CA.
          trust_bundle_path = bootstrapBundle;
          trust_bundle_format = "pem";
          rebootstrap_mode = "auto";
          rebootstrap_delay = "1m";
          # JWKS lookups need no identity: the keys are public anyway, and the
          # discovery provider then needs no registration entry of its own.
          allow_unauthenticated_verifiers = true;
        };
        plugins = {
          KeyManager.disk.plugin_data.directory = "$STATE_DIRECTORY";
          NodeAttestor.tpm.plugin_data = { };
          WorkloadAttestor.unix.plugin_data = { };
          WorkloadAttestor.systemd.plugin_data = { };
        };
      };
    };
    systemd.services.spire-agent = {
      requires = [ "spire-server.service" ];
      after = [ "spire-server.service" ];
      serviceConfig = hardening // {
        # root, outside the sandbox: the server's admin socket is root-only
        ExecStartPre = "+${pkgs.writeShellScript "spire-agent-bootstrap-bundle" ''
          set -e
          export SPIRE_SERVER_PRIVATE_SOCKET=${server.settings.server.socket_path}
          ${waitForServer}
          # /run is root's alone, so no one else can have created this
          install -d -m 0755 "$(dirname ${bootstrapBundle})"
          ${lib.getExe' server.package "spire-server"} bundle show > "${bootstrapBundle}.new"
          mv "${bootstrapBundle}.new" "${bootstrapBundle}"
        ''}";
        DevicePolicy = "closed";
        DeviceAllow = [ "/dev/tpmrm0 rw" ];
        RestartSec = 5;
      };
    };

    systemd.services.spire-entries = {
      description = "Reconcile SPIRE registration entries with my.spire";
      requires = [ "spire-server.service" ];
      after = [ "spire-server.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ entriesFile ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe reconcileEntries;
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    systemd.services.${discoveryUnit} = {
      description = "SPIRE OIDC discovery provider";
      wants = [ "spire-agent.service" ];
      after = [ "spire-agent.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = hardening // {
        ExecStart = "${lib.getExe' server.package.oidc "oidc-discovery-provider"} -config ${discoveryConfig}";
        DynamicUser = true;
        RuntimeDirectory = discoveryUnit;
        RuntimeDirectoryMode = "0755";
        # Unix sockets only: the Workload API and its own listener
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        PrivateDevices = true;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    systemd.user.services.spiffe-helper-aws = lib.mkIf (cfg.users != [ ]) {
      description = "Fresh SPIRE token for AWS in $XDG_RUNTIME_DIR/spiffe";
      wantedBy = [ "default.target" ];
      # one instance per listed user; "|" makes the conditions alternatives
      unitConfig.ConditionUser = map (user: "|${user}") cfg.users;
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.spiffe-helper} -config ${helperConfig}";
        RuntimeDirectory = "spiffe";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = "%t/spiffe";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
  };
}
