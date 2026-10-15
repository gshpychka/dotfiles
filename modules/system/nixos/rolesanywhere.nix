# AWS credentials for this machine's Unix users through IAM Roles Anywhere,
# from a CA whose key never leaves this machine's TPM2. The code is
# packages/rolesanywhere; the AWS side is infra/aws.
#
# - CA: rolesanywhere-ca, at boot and on deploy, keeps one key the TPM2
#   generated, with a self-signed CA certificate, in /var/lib/rolesanywhere.
#   The key has no auth value: the TPM2 signs with it only while PCR 7 (the
#   Secure Boot state) is what it was when the key was created, which it
#   checks itself, so nothing secret exists outside the TPM2. Another OS on
#   the disk, or this one booted with Secure Boot off, can't use it. The CA is
#   replaced when the TPM2 stops signing with it (after a Secure Boot key or
#   dbx update, or a TPM2 clear), or on `sudo rolesanywhere-replace-ca`.
# - Trust: AWS trusts the CA certificate my.rolesAnywhere.caCertificate names,
#   as a Roles Anywhere trust anchor. Every new CA is registered by hand; see
#   that option. Until then, no certificates are issued.
# - Identity: a client certificate's subject is "<hostname>:<user>", the user
#   the kernel reports for the connecting process (SO_PEERCRED). Callers send
#   nothing, so there is no secret to steal and no request to parse. Any
#   process running as a client user can get that user's certificate.
# - Issuance: one short-lived, sandboxed process per connection, without
#   network access, generates a throwaway key in memory and has the TPM2 sign
#   a certificate for it, valid for certificateLifetime, and returns both.
#   rolesanywhere-credentials hands them to aws_signing_helper in memory-only
#   files, which trades them for AWS credentials.
# - Root on the running machine can issue any client's certificate, but
#   can't take the CA key away.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.rolesAnywhere;
  unitName = "rolesanywhere";
  caUnit = "${unitName}-ca";
  stateDirectory = "/var/lib/${unitName}";
  socketPath = "/run/${unitName}/certificate.sock";
  # not unitName: DynamicUser= names the issuing processes' user and group
  # after the unit, and refuses to start when that group already exists
  clientGroup = "${unitName}-clients";
  # symlink in stateDirectory to the current CA's directory
  currentLink = "current";
  currentCa = "${stateDirectory}/${currentLink}";
  # file in stateDirectory whose presence asks for the CA's replacement
  replaceRequest = "replace-ca";
  # What rolesanywhere-ca writes to ${stateDirectory}/<SKI>/, each file handed
  # to the issuing process as the credential of the same name.
  caFiles = {
    # the key's public area (TPM2B_PUBLIC)
    public = "key.pub";
    # the private key, encrypted by the TPM2's storage key (TPM2B_PRIVATE)
    private = "key.priv";
    # the self-signed CA certificate, the one to register with AWS
    certificate = "ca.pem";
  };

  tpmDevice = "/dev/tpmrm0";

  issuerConfig = pkgs.writeText "${unitName}.json" (
    builtins.toJSON {
      name = config.networking.hostName;
      inherit (cfg) clients;
      certificateLifetimeSeconds = cfg.certificateLifetime;
      # interpolating a path in the repository copies it to the store, so the
      # deployed machine has it
      registeredCertificate = lib.mapNullable (path: "${path}") cfg.caCertificate;
      inherit
        stateDirectory
        currentLink
        replaceRequest
        caFiles
        ;
      tpm2Tools = "${pkgs.tpm2-tools}/bin";
      # the kernel's TPM2 resource manager, which flushes whatever a process
      # loaded into the TPM2 when it exits
      tcti = "device:${tpmDevice}";
    }
  );

  package = pkgs.callPackage ../../../packages/rolesanywhere { };
  tool = lib.getExe package;

  replaceCa = pkgs.writeShellApplication {
    name = "rolesanywhere-replace-ca";
    text = ''
      # asks rolesanywhere-ca for a new CA, which then needs registering with AWS
      install -m 0600 /dev/null ${stateDirectory}/${replaceRequest}
      systemctl restart ${caUnit}.service
    '';
  };

  credentials = pkgs.writeShellApplication {
    name = "rolesanywhere-credentials";
    text = ''
      exec ${lib.getExe' package "rolesanywhere-credentials"} \
        --socket ${socketPath} --unit ${unitName} \
        --helper ${lib.getExe pkgs.aws-signing-helper} "$@"
    '';
  };

  # Sandboxing shared by the CA and issuing processes.
  sandbox = {
    PrivateNetwork = true;
    IPAddressDeny = "any";
    RestrictAddressFamilies = "AF_UNIX";
    CapabilityBoundingSet = "";
    NoNewPrivileges = true;
    # The TPM2 resource manager is the only device. Access to it grants the
    # whole TPM2 (other keys, extending PCRs), which is why nothing a caller
    # sends is ever read.
    PrivateDevices = true;
    BindPaths = [ tpmDevice ];
    DeviceAllow = [ "${tpmDevice} rw" ];
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    ProcSubset = "pid";
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "@system-service"
      "~@privileged @resources"
    ];
    UMask = "0077";
  };
in
{
  options.my.rolesAnywhere = {
    enable = lib.mkEnableOption "AWS credentials for local users through IAM Roles Anywhere, from a CA in this machine's TPM2";
    clients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Unix users that may get a certificate for themselves, with subject
        "<hostname>:<user>". A new member's group applies from their next login.
      '';
    };
    caCertificate = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The CA certificate registered with AWS as this machine's Roles
        Anywhere trust anchor: infra/aws reads the same file. Certificates are
        issued only while it is the machine's current CA. To register a new
        CA (the first one, or a replacement rolesanywhere-ca logs), copy
        ${currentCa}/${caFiles.certificate} from the machine into this file,
        apply infra/aws, and deploy.
      '';
    };
    certificateLifetime = lib.mkOption {
      type = lib.types.ints.between 60 3600;
      default = 300;
      description = ''
        Seconds a client certificate stays valid. A certificate is traded for
        AWS credentials once, right after it is issued, so this only bounds
        how long a leaked certificate and key are useful.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (user: config.users.users ? ${user}) cfg.clients;
        message = "my.rolesAnywhere.clients must name users.users entries.";
      }
    ];

    environment.systemPackages = [
      credentials
      replaceCa
    ];
    users.groups.${clientGroup}.members = cfg.clients;
    # makes ${tpmDevice} accessible to its group, tssGroup
    security.tpm2.enable = true;

    systemd.services.${caUnit} = {
      description = "IAM Roles Anywhere CA in the TPM2";
      # at boot, and on deploys that change it: RemainAfterExit keeps it
      # active, so switching restarts it
      wantedBy = [ "multi-user.target" ];
      serviceConfig = sandbox // {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${tool} ca ${issuerConfig}";
        # root's, readable by all: the CA certificate is public
        StateDirectory = unitName;
        StateDirectoryMode = "0755";
        # a tmpfs, for the TPM2 context files
        RuntimeDirectory = caUnit;
        RuntimeDirectoryMode = "0700";
        PrivateTmp = true;
      };
    };

    # One sandboxed process per connection.
    systemd.sockets.${unitName} = {
      description = "IAM Roles Anywhere certificate issuer";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = socketPath;
        Accept = true;
        SocketUser = "root";
        SocketGroup = clientGroup;
        SocketMode = "0660";
        # bounds the instances a looping client can spawn; on a Unix
        # socket the per-source limit applies per peer UID
        MaxConnections = 16;
        MaxConnectionsPerSource = 4;
        RemoveOnStop = true;
      };
    };

    systemd.services."${unitName}@" = {
      description = "IAM Roles Anywhere certificate issuer, one connection";
      unitConfig = {
        # instances of failed refusals would otherwise pile up in `systemctl --failed`
        CollectMode = "inactive-or-failed";
        # rolesanywhere-ca creates the first CA
        ConditionPathExists = currentCa;
      };
      serviceConfig = sandbox // {
        ExecStart = "${tool} serve ${issuerConfig}";
        StandardInput = "socket";
        # logs go to the journal, never down the connection
        StandardOutput = "journal";
        StandardError = "journal";
        LoadCredential = map (name: "${name}:${currentCa}/${name}") (lib.attrValues caFiles);
        # bounds a stuck instance; a normal one answers in about a second,
        # but a slow TPM2 can take several
        RuntimeMaxSec = 30;
        DynamicUser = true;
        # No PrivateUsers=: inside a user namespace every caller's UID
        # reads as nobody, and SO_PEERCRED would identify no one.
        SupplementaryGroups = [ config.security.tpm2.tssGroup ];
      };
    };
  };
}
