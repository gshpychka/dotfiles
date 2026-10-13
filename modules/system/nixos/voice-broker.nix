# OpenAI voice broker for the Voice PEs (packages/voice-broker).
# Setup steps that can't be declared here: scripts/voice-pe/runbook.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.voice-broker;
  openclaw = config.my.openclaw;
  json = pkgs.formats.json { };
  voicePes = lib.filterAttrs (_: host: host.voiceArea != null) config.my.hosts;
  voicePeIps = map (host: host.lanIp) (lib.attrValues voicePes);
  nftables = config.networking.firewall.backend == "nftables";

  user = "voice-broker";
  stateDirectory = "voice-broker";
  recordingsDir = "${stateDirectory}/recordings";

  # sopsFile keys, handed to the service as systemd credentials under the same names.
  credentialNames = [
    "openai-api-key"
    "device-token"
  ];
  openclawCredential = "openclaw-secret";
  identityCredential = "identity";
  credential = name: "/run/credentials/voice-broker.service/${name}";
  # sops-nix secret names are host-global, so they carry the service name
  sopsName = name: "voice-broker/${name}";
in
{
  options.my.voice-broker = {
    enable = lib.mkEnableOption "the Voice PE broker";

    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "SOPS file holding flat keys openai-api-key and device-token.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 10310;
      description = "TCP port the Voice PEs connect to.";
    };

    recordings = {
      enable = lib.mkEnableOption ''
        recording every conversation's mic, echo reference and echo-cancelled
        audio, for tuning echo cancellation. That is household audio, so leave
        it off otherwise'';
      retention = lib.mkOption {
        type = lib.types.str;
        default = "7d";
        description = "systemd-tmpfiles age past which recordings are deleted, whether or not recording is on.";
      };
    };

    identityFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "${openclaw.workspace}/IDENTITY.md";
      defaultText = lib.literalExpression ''"''${config.my.openclaw.workspace}/IDENTITY.md"'';
      description = ''
        The assistant's description of itself, read at each broker start to
        lead the Live instructions. The instructions stand alone while it is
        missing or empty, and with null.
      '';
    };

    settings = lib.mkOption {
      inherit (json) type;
      default = { };
      description = ''
        Broker configuration (packages/voice-broker/src/voice_broker/config.py):
        the Live session, the OpenClaw consult instructions, how much of the
        agent's conversation the voice starts with, and the conversation
        timeouts. The listener, credentials, devices, recordings and the
        gateway's address and session come from this module.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = openclaw.enable && openclaw.responsesEndpoint.enable;
        message = "my.voice-broker hands delegated work to OpenClaw on this host; enable my.openclaw and its responsesEndpoint.";
      }
    ];

    my.voice-broker.settings = {
      listen_host = "0.0.0.0";
      listen_port = cfg.port;
      device_token_file = credential "device-token";
      openai_api_key_file = credential "openai-api-key";
      devices = lib.mapAttrsToList (name: host: {
        inherit name;
        address = host.lanIp;
        area = host.voiceArea;
      }) voicePes;
      recordings_dir = if cfg.recordings.enable then "/var/lib/${recordingsDir}" else null;
      openclaw = {
        url = openclaw.localUrl;
        token_file = credential openclawCredential;
        session_key = openclaw.mainSessionKey;
      };
      live = lib.optionalAttrs (cfg.identityFile != null) {
        identity_file = credential identityCredential;
      };
    };

    sops.secrets = lib.listToAttrs (
      map (
        name:
        lib.nameValuePair (sopsName name) {
          inherit (cfg) sopsFile;
          key = name;
        }
      ) credentialNames
    );

    # Static: loopback access to the OpenClaw gateway is granted per user.
    users.users.${user} = {
      isSystemUser = true;
      group = user;
    };
    users.groups.${user} = { };

    systemd.services.voice-broker = {
      description = "OpenAI Live voice broker";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.voice-broker} --config ${json.generate "voice-broker.json" cfg.settings}";
        LoadCredential =
          map (name: "${name}:${config.sops.secrets.${sopsName name}.path}") credentialNames
          ++ [ "${openclawCredential}:${openclaw.gatewaySecretFile}" ]
          ++ lib.optional (cfg.identityFile != null) "${identityCredential}:${cfg.identityFile}";
        # the identity while identityFile is missing; a LoadCredential= that
        # finds no file falls back to it (systemd.exec(5), SetCredential=)
        SetCredential = lib.optional (cfg.identityFile != null) "${identityCredential}:";
        User = user;
        Group = user;
        StateDirectory = stateDirectory;
        Restart = "on-failure";
        RestartSec = 5;
        # Audio processing is latency-sensitive; keep it ahead of batch work.
        Nice = -5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RemoveIPC = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
    };

    systemd.tmpfiles.settings.voice-broker."/var/lib/${recordingsDir}".e.age = cfg.recordings.retention;

    # Only the Voice PEs may open conversations: every one is billed to the OpenAI key.
    networking.firewall = {
      extraInputRules = lib.mkIf (nftables && voicePes != { }) ''
        ip saddr { ${lib.concatStringsSep ", " voicePeIps} } tcp dport ${toString cfg.port} accept
      '';
      extraCommands = lib.mkIf (!nftables && voicePes != { }) ''
        iptables -A nixos-fw -p tcp -s ${lib.concatStringsSep "," voicePeIps} --dport ${toString cfg.port} -j nixos-fw-accept
      '';
    };
  };
}
