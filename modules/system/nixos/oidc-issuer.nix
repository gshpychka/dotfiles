# OIDC token issuer: processes on this machine trade their Unix identity for a
# short-lived token from https://tokens.glib.sh/<hostname>, which AWS STS can
# trust the same way it trusts GitHub Actions' tokens. Each machine that
# enables this is its own issuer (my.oidcIssuer.issuers.<hostname> in
# modules/common/oidc-issuer.nix), with its own key and AWS provider.
#
# - Identity: a token's subject is "<hostname>:<user>", the user the kernel
#   reports for the connecting process (SO_PEERCRED). Callers send nothing, so
#   there is no secret to steal and no request to parse. Any process running
#   as a client user can get that user's token.
# - Access: only users in my.oidcIssuer.clients. The socket is restricted to
#   their group, and oidc-issuer.py checks the list again.
# - Key: ES256, generated inside this machine's TPM2, which refuses to export
#   it or duplicate it to another TPM2. On disk are only the key wrapped by
#   this TPM2's storage key, which nothing else can load, and the key's random
#   auth value, sealed with systemd-creds to both the TPM2 and the host key in
#   /var/lib/systemd: it only decrypts on this machine, booted through its own
#   Secure Boot chain (PCR 7). Each short-lived, sandboxed minting process
#   gets these from systemd and has the TPM2 sign (oidc-issuer.py, via
#   tpm2-tools). Root on the running machine can sign too, but can't take the
#   key away, so an attacker's signing ends with their access to the machine.
#   Still rotate after a compromise: with copies of the files and the auth
#   value, any later TPM2 access on the machine is enough to sign again.
# - Publishing: issuing machines serve nothing publicly. buoy serves every
#   issuer's discovery document and JWKS, built from its publicKeys
#   (machines/buoy/oidc-discovery.nix).
#
# Enabling on a machine (needs a TPM2; check with `systemd-analyze has-tpm2`):
#   add `<hostname>.publicKeys = [ ];` to my.oidcIssuer.issuers in
#   modules/common/oidc-issuer.nix
#   in the machine's config: my.oidcIssuer = { enable = true; clients = [ <users> ]; };
#   deploy it, then bootstrap a key as below
#
# Bootstrap and key rotation:
#   ssh <machine> sudo oidc-issuer-keygen   # creates a new key in the TPM2, prints its public half
#   (also after a Secure Boot key or dbx update, which leaves the sealed auth
#   value unusable: it is bound to PCR 7; and after clearing the TPM2, which
#   destroys the key)
#   add the printed entry to my.oidcIssuer.issuers.<hostname>.publicKeys
#   set my.oidcIssuer.activeKid in the machine's config to the printed kid
#   deploy buoy (publishes the key), wait my.oidcIssuer.jwksCacheSeconds so
#   relying parties' cached key sets include it, then deploy the machine
#   (signs with it)
#   after a rotation, once my.oidcIssuer.tokenLifetime has passed, drop the old
#   entry and delete /var/lib/oidc-issuer/<old kid>
#
# AWS side, once per issuer and account:
#   aws iam create-open-id-connect-provider --url https://tokens.glib.sh/<hostname> --client-id-list sts.amazonaws.com
#   each role's trust policy: Principal.Federated = that provider's ARN,
#   Action = sts:AssumeRoleWithWebIdentity, Condition.StringEquals =
#   { "tokens.glib.sh/<hostname>:aud": "sts.amazonaws.com",
#     "tokens.glib.sh/<hostname>:sub": "<hostname>:<user>" }
#
# Usage, as a client user:
#   oidc-token claims
#   ~/.aws/config: credential_process = oidc-token aws --role-arn <role ARN>
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.oidcIssuer;
  inherit (config.networking) hostName;
  # this machine's entry in the fleet's issuer list; null until it is added
  issuer = cfg.issuers.${hostName} or null;

  unitName = "oidc-issuer";
  stateDirectory = "/var/lib/${unitName}";
  socketPath = "/run/${unitName}/token.sock";
  clientGroup = "oidc-token";
  # What oidc-issuer-keygen writes to ${stateDirectory}/<kid>/, each file
  # handed to the minting process as the credential of the same name.
  keyFiles = {
    # the key's public area (TPM2B_PUBLIC)
    public = "key.pub";
    # the private key, encrypted by the TPM2's storage key (TPM2B_PRIVATE)
    private = "key.priv";
    # the auth value every use of the key needs, sealed with systemd-creds
    # under this name; systemd refuses to load it under any other
    auth = "key.auth";
  };

  tpmDevice = "/dev/tpmrm0";

  activeKey = lib.findFirst (key: key.kid == cfg.activeKid) null (
    if issuer == null then [ ] else issuer.publicKeys
  );

  issuerConfig = pkgs.writeText "${unitName}.json" (
    builtins.toJSON {
      # the issuer's name, also the prefix of every subject
      name = hostName;
      issuer = issuer.url;
      inherit (cfg) audience clients;
      tokenLifetimeSeconds = cfg.tokenLifetime;
      activeKey = if activeKey == null then null else { inherit (activeKey) kid x y; };
      inherit (cfg) jwksCacheSeconds;
      inherit stateDirectory keyFiles;
      systemdCreds = lib.getExe' config.systemd.package "systemd-creds";
      tpm2Tools = "${pkgs.tpm2-tools}/bin";
      # the kernel's TPM2 resource manager, which flushes whatever a process
      # loaded into the TPM2 when it exits
      tcti = "device:${tpmDevice}";
    }
  );

  # ruff format owns line width, so flake8's E501 is ignored.
  issuerTool = pkgs.writers.writePython3Bin unitName {
    libraries = ps: [ ps.cryptography ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./oidc-issuer.py);

  keygen = pkgs.writeShellApplication {
    name = "oidc-issuer-keygen";
    text = ''exec ${lib.getExe issuerTool} keygen ${issuerConfig} "$@"'';
  };

  oidcToken = pkgs.writers.writePython3Bin "oidc-token" { flakeIgnore = [ "E501" ]; } (
    lib.replaceStrings [ "@socketPath@" "@issuerUnit@" ] [ socketPath unitName ] (
      builtins.readFile ./oidc-token.py
    )
  );
in
{
  options.my.oidcIssuer = {
    enable = lib.mkEnableOption "the OIDC token issuer for local users";
    activeKid = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        kid of the published key to sign with, as printed by
        `oidc-issuer-keygen`. Null until the first key is published; the
        machine issues no tokens until then.
      '';
    };
    clients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Unix users that may get a token for themselves, with subject
        "<hostname>:<user>". A new member's group applies from their next login.
      '';
    };
    tokenLifetime = lib.mkOption {
      type = lib.types.ints.between 60 3600;
      default = 300;
      description = ''
        Seconds a token stays valid. A token is only exchanged once, right
        after it is issued, so this only bounds how long a leaked one is useful.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = issuer != null;
            message = "my.oidcIssuer.enable needs an issuer for this machine: add my.oidcIssuer.issuers.${hostName} in modules/common/oidc-issuer.nix.";
          }
          {
            assertion = cfg.activeKid == null || activeKey != null;
            message = "my.oidcIssuer.activeKid ${toString cfg.activeKid} is not in my.oidcIssuer.issuers.${hostName}.publicKeys, so AWS could not verify its tokens.";
          }
          {
            assertion = lib.all (user: config.users.users ? ${user}) cfg.clients;
            message = "my.oidcIssuer.clients must name users.users entries.";
          }
        ];
        warnings = lib.optional (cfg.activeKid == null) ''
          my.oidcIssuer: no active signing key, so no tokens are issued yet.
          Run `sudo oidc-issuer-keygen` on ${hostName} and follow its output.
        '';

        environment.systemPackages = [
          keygen
          oidcToken
        ];
        systemd.tmpfiles.settings.${unitName}.${stateDirectory}.d = {
          user = "root";
          group = "root";
          mode = "0700";
        };
        users.groups.${clientGroup}.members = cfg.clients;
        # makes ${tpmDevice} accessible to its group, tssGroup
        security.tpm2.enable = true;
      }

      (lib.mkIf (cfg.activeKid != null) (
        let
          keyDirectory = "${stateDirectory}/${cfg.activeKid}";
        in
        {
          # One sandboxed process per connection, so no process holds the auth
          # value between requests.
          systemd.sockets.${unitName} = {
            description = "OIDC token issuer";
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
            description = "OIDC token issuer, one connection";
            # instances of failed refusals would otherwise pile up in `systemctl --failed`
            unitConfig.CollectMode = "inactive-or-failed";
            serviceConfig = {
              ExecStart = "${lib.getExe issuerTool} serve ${issuerConfig}";
              StandardInput = "socket";
              # logs go to the journal, never down the connection
              StandardOutput = "journal";
              StandardError = "journal";
              LoadCredential = map (name: "${name}:${keyDirectory}/${name}") [
                keyFiles.public
                keyFiles.private
              ];
              LoadCredentialEncrypted = "${keyFiles.auth}:${keyDirectory}/${keyFiles.auth}";
              # bounds a stuck instance; a normal one answers in about a second,
              # but a slow TPM2 can take several
              RuntimeMaxSec = 30;

              DynamicUser = true;
              # No PrivateUsers=: inside a user namespace every caller's UID
              # reads as nobody, and SO_PEERCRED would identify no one.
              PrivateNetwork = true;
              IPAddressDeny = "any";
              RestrictAddressFamilies = "AF_UNIX";
              CapabilityBoundingSet = "";
              NoNewPrivileges = true;
              # The TPM2 resource manager is the only device, reached through its
              # group. The group grants the whole TPM2 (other keys, extending
              # PCRs), which is why nothing a caller sends is ever read.
              PrivateDevices = true;
              BindPaths = [ tpmDevice ];
              DeviceAllow = [ "${tpmDevice} rw" ];
              SupplementaryGroups = [ config.security.tpm2.tssGroup ];
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
          };
        }
      ))
    ]
  );
}
