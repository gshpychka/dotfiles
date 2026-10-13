# OpenAI voice broker for the Voice PEs (packages/voice-broker).
# Setup steps that can't be declared here: scripts/voice-pe/runbook.md.
#
# Imperative, once, with the YubiKey or the op age key: the long-lived token
# of a dedicated Home Assistant user, with which the broker rings a speaker:
#   sops set <sopsFile> '["home-assistant-token"]' '"<token>"'
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
  runtimeDirectory = "voice-broker";
  # the agent's way to open a conversation on a speaker
  callSocket = "/run/${runtimeDirectory}/call.sock";

  # ESPHome names a Voice PE after upstream's device name and the last three
  # bytes of its MAC (name_add_mac_suffix); Home Assistant exposes the
  # firmware's start_conversation action (scripts/voice-pe/voice-pe.yaml) under it.
  callAction =
    host:
    "esphome.home_assistant_voice_${lib.toLower (lib.concatStrings (lib.drop 3 (lib.splitString ":" host.mac)))}_start_conversation";

  # sopsFile keys, handed to the service as systemd credentials under the same names.
  credentialNames = [
    "openai-api-key"
    "device-token"
    "home-assistant-token"
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
      description = "SOPS file holding flat keys openai-api-key, device-token and home-assistant-token.";
    };

    homeAssistant.url = lib.mkOption {
      type = lib.types.str;
      description = "Base URL of the Home Assistant whose ESPHome actions ring the speakers.";
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
        timeouts. The listener, credentials, devices, recordings, calls and
        the gateway's address and session come from this module.
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
        call_action = callAction host;
      }) voicePes;
      recordings_dir = if cfg.recordings.enable then "/var/lib/${recordingsDir}" else null;
      openclaw = {
        url = openclaw.localUrl;
        token_file = credential openclawCredential;
        session_key = openclaw.mainSessionKey;
      };
      calls = {
        socket = callSocket;
        home_assistant_url = cfg.homeAssistant.url;
        home_assistant_token_file = credential "home-assistant-token";
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
    # the group owns the call socket
    users.users.${config.services.openclaw-gateway.user}.extraGroups = [ user ];

    my.openclaw.extraPackages = [ pkgs.voice-broker ];
    my.openclaw.skills.voice-call = {
      description = "Open a spoken conversation on a speaker to tell the owner something and hear the reply, in place of a Home Assistant announcement.";
      text = ''
        The speakers, by area: ${
          lib.concatStringsSep ", " (map (host: host.voiceArea) (lib.attrValues voicePes))
        }.
        To open a conversation on one:

            voice-broker-call --socket ${callSocket} <Area> "<what to tell the owner>"

        The speaker chimes, says the opening in its own words, then listens;
        the owner's reply reaches you as a turn of this session, like anything
        said at a speaker. The command prints `started` once the speaker has
        picked up, or `failed: <reason>` when the speaker is muted, in a
        conversation, or unreachable. Keep the opening to one or two spoken
        sentences; details can follow once the owner engages. A Home Assistant
        announcement remains the way to say something that needs no reply.
      '';
    };

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
        # finds no file falls back to it (systemd.exec(5), SetCredential=).
        # An escaped empty line: systemd drops an empty value, and the broker trims it.
        SetCredential = lib.optional (cfg.identityFile != null) "${identityCredential}:\\n";
        User = user;
        Group = user;
        StateDirectory = stateDirectory;
        # holds the call socket; group members reach it
        RuntimeDirectory = runtimeDirectory;
        RuntimeDirectoryMode = "0750";
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
