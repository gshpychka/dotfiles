# OIDC token issuer: processes on reaper trade their Unix identity for a
# short-lived token from https://tokens.glib.sh, which AWS STS can trust the
# same way it trusts GitHub Actions' tokens.
#
# - Identity: a token's subject is "reaper:<user>", the user the kernel reports
#   for the connecting process (SO_PEERCRED). Callers send nothing, so there is
#   no secret to steal and no request to parse. Any process running as a client
#   user can get that user's token.
# - Access: only users in my.oidcIssuer.clients. The socket is restricted to
#   their group, and issuer.py checks the list again.
# - Key: ES256, generated on reaper and sealed with systemd-creds to both the
#   TPM2 and the host key in /var/lib/systemd, so the sealed file only
#   decrypts on this machine, booted through its own Secure Boot chain (PCR 7).
#   It is never in git, a sops file or the Nix store; systemd decrypts it into
#   each short-lived, sandboxed minting process. Root on the running machine
#   can still read it, so a root compromise means rotating the key.
#   (`oidc-issuer-keygen --no-tpm` seals with the host key alone, for a
#   machine without a TPM2.)
# - Publishing: reaper serves nothing publicly. buoy serves the discovery
#   document and JWKS, built from my.oidcIssuer.publicKeys
#   (machines/buoy/oidc-discovery.nix).
#
# Bootstrap and key rotation:
#   ssh reaper sudo oidc-issuer-keygen   # seals a new key to the TPM2, prints its public half
#   (also after a Secure Boot key or dbx update, which leaves the sealed key
#   unusable: it is bound to PCR 7)
#   add the printed entry to my.oidcIssuer.publicKeys (modules/common/oidc-issuer.nix)
#   set my.oidcIssuer.activeKid (machines/reaper/default.nix) to the printed kid
#   deploy buoy (publishes the key), wait my.oidcIssuer.jwksCacheSeconds so
#   relying parties' cached key sets include it, then deploy reaper (signs with it)
#   after a rotation, once my.oidcIssuer.tokenLifetime has passed, drop the old
#   entry and delete /var/lib/oidc-issuer/<old kid>.cred
#
# AWS side, once per account:
#   aws iam create-open-id-connect-provider --url https://tokens.glib.sh --client-id-list sts.amazonaws.com
#   each role's trust policy: Principal.Federated = that provider's ARN,
#   Action = sts:AssumeRoleWithWebIdentity, Condition.StringEquals =
#   { "tokens.glib.sh:aud": "sts.amazonaws.com", "tokens.glib.sh:sub": "reaper:<user>" }
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

  unitName = "oidc-issuer";
  stateDirectory = "/var/lib/${unitName}";
  socketPath = "/run/${unitName}/token.sock";
  clientGroup = "oidc-token";
  # name sealed into every key file; systemd refuses to load a file sealed
  # under a different name
  credentialName = "signing-key";

  activeKey = lib.findFirst (key: key.kid == cfg.activeKid) null cfg.publicKeys;

  issuerConfig = pkgs.writeText "${unitName}.json" (
    builtins.toJSON {
      issuer = cfg.url;
      inherit (cfg) audience clients;
      subjectPrefix = config.networking.hostName;
      tokenLifetimeSeconds = cfg.tokenLifetime;
      activeKey = if activeKey == null then null else { inherit (activeKey) kid x y; };
      inherit (cfg) jwksCacheSeconds;
      inherit stateDirectory credentialName;
      systemdCreds = lib.getExe' config.systemd.package "systemd-creds";
    }
  );

  # ruff format owns line width, so flake8's E501 is ignored.
  issuer = pkgs.writers.writePython3Bin unitName {
    libraries = ps: [
      ps.cryptography
      ps.pyjwt
    ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./issuer.py);

  keygen = pkgs.writeShellApplication {
    name = "oidc-issuer-keygen";
    text = ''exec ${lib.getExe issuer} keygen ${issuerConfig} "$@"'';
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
        `oidc-issuer-keygen`. Null until the first key is published; reaper
        issues no tokens until then.
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
            assertion = cfg.activeKid == null || activeKey != null;
            message = "my.oidcIssuer.activeKid ${toString cfg.activeKid} is not in my.oidcIssuer.publicKeys, so AWS could not verify its tokens.";
          }
          {
            assertion = lib.all (user: config.users.users ? ${user}) cfg.clients;
            message = "my.oidcIssuer.clients must name users.users entries.";
          }
        ];
        warnings = lib.optional (cfg.activeKid == null) ''
          my.oidcIssuer: no active signing key, so no tokens are issued yet.
          Run `sudo oidc-issuer-keygen` on ${config.networking.hostName} and follow its output.
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
      }

      (lib.mkIf (cfg.activeKid != null) {
        # One sandboxed process per connection, so no process holds the key
        # between requests.
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
            ExecStart = "${lib.getExe issuer} serve ${issuerConfig}";
            StandardInput = "socket";
            # logs go to the journal, never down the connection
            StandardOutput = "journal";
            StandardError = "journal";
            LoadCredentialEncrypted = "${credentialName}:${stateDirectory}/${cfg.activeKid}.cred";
            # bounds a stuck instance; a normal one answers in well under a
            # second, but a slow firmware TPM can take seconds to unseal
            RuntimeMaxSec = 30;

            DynamicUser = true;
            # No PrivateUsers=: inside a user namespace every caller's UID
            # reads as nobody, and SO_PEERCRED would identify no one.
            PrivateNetwork = true;
            IPAddressDeny = "any";
            RestrictAddressFamilies = "AF_UNIX";
            CapabilityBoundingSet = "";
            NoNewPrivileges = true;
            PrivateDevices = true;
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
      })
    ]
  );
}
