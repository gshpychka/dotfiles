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

  # Each routing provider's default model. gpt-6-luna is the only model Decisions takes so far;
  # typesafe/jev-1.13 is the Jev the frozen routing benchmarks measured (its dated endpoint
  # typesafe/jev-1.13-20260917 answered every call).
  routingModels = {
    decisions = "gpt-6-luna";
    jev = "typesafe/jev-1.13";
  };
  # The OpenRouter key, only while Jev classifies: Decisions needs none.
  jevRouting = cfg.routing.enable && cfg.routing.provider == "jev";
  openRouterKey = "openrouter-api-key";
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

    routing = {
      enable = lib.mkEnableOption ''
        classifying each delegated request (with `provider`) and running it on
        Home Assistant's conversation agent or on OpenClaw, whichever owns it.
        Off, OpenClaw answers everything. Every Voice PE needs homeAssistantDeviceId'';
      provider = lib.mkOption {
        type = lib.types.enum (lib.attrNames routingModels);
        default = "decisions";
        description = ''
          The classifier (packages/voice-broker/src/voice_broker/routing.py):
          `decisions`, OpenAI Decisions on the broker's OpenAI key; or `jev`,
          TypeSafe Jev through OpenRouter's System One API, on the OpenRouter
          key of `openRouter.sopsFile`. One call per request either way; a
          failure runs nothing and never falls back to the other.
        '';
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = routingModels.${cfg.routing.provider};
        defaultText = lib.literalMD "per provider: `gpt-6-luna` for decisions, `typesafe/jev-1.13` for jev";
        description = "The provider's model.";
      };
      openRouter.sopsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "SOPS file holding the flat key ${openRouterKey}, read only when provider is jev.";
      };
      timeoutSeconds = lib.mkOption {
        # The bounds are config.py's MIN_ROUTING_TIMEOUT_S and MAX_ROUTING_TIMEOUT_S, explained there.
        # A spoken request usually reaches the classifier cold, on a new connection, and 1.5 s ran out
        # with Decisions in production. 30 is a diagnostic allowance, not a latency target.
        type = lib.types.numbers.between 3 30;
        default = 4;
        description = "Classification time limit, connection setup included; past it nothing runs and the user is asked again.";
      };
      pipeline = lib.mkOption {
        type = lib.types.str;
        description = "ID of the Assist pipeline whose conversation agent home requests go to.";
      };
      pendingQuestionSeconds = lib.mkOption {
        type = lib.types.numbers.between 1 299;
        default = 60;
        description = "How long a question Home Assistant asked stays answerable; Home Assistant itself forgets after 5 minutes.";
      };
      settleSeconds = lib.mkOption {
        type = lib.types.numbers.between 0.05 1;
        default = 0.35;
        description = "Transcript quiet that marks a delegated request complete.";
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
      {
        assertion =
          !cfg.routing.enable || lib.all (host: host.homeAssistantDeviceId != null) (lib.attrValues voicePes);
        message = "my.voice-broker.routing runs home requests as each Voice PE; set my.hosts.<name>.homeAssistantDeviceId for every one.";
      }
      {
        # Each provider's API takes only its own models; another's fails every request at runtime.
        assertion =
          !cfg.routing.enable
          || (
            if cfg.routing.provider == "jev" then
              lib.hasPrefix "typesafe/jev-" cfg.routing.model
            else
              !lib.hasInfix "/" cfg.routing.model
          );
        message = "my.voice-broker.routing.model ${cfg.routing.model} is not a ${cfg.routing.provider} model.";
      }
      {
        assertion = !jevRouting || cfg.routing.openRouter.sopsFile != null;
        message = "my.voice-broker.routing.provider jev classifies on OpenRouter; set routing.openRouter.sopsFile.";
      }
    ];

    my.voice-broker.settings = {
      listen_host = "0.0.0.0";
      listen_port = cfg.port;
      device_token_file = credential "device-token";
      openai_api_key_file = credential "openai-api-key";
      devices = lib.mapAttrsToList (
        name: host:
        {
          inherit name;
          address = host.lanIp;
          area = host.voiceArea;
          call_action = callAction host;
        }
        // lib.optionalAttrs (host.homeAssistantDeviceId != null) {
          home_assistant_device_id = host.homeAssistantDeviceId;
        }
      ) voicePes;
      routing = lib.mkIf cfg.routing.enable (
        {
          inherit (cfg.routing) provider model pipeline;
          timeout_s = cfg.routing.timeoutSeconds;
          pending_question_s = cfg.routing.pendingQuestionSeconds;
          settle_s = cfg.routing.settleSeconds;
        }
        // lib.optionalAttrs jevRouting {
          api_key_file = credential openRouterKey;
        }
      );
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

    sops.secrets =
      lib.listToAttrs (
        map (
          name:
          lib.nameValuePair (sopsName name) {
            inherit (cfg) sopsFile;
            key = name;
          }
        ) credentialNames
      )
      // lib.optionalAttrs jevRouting {
        ${sopsName openRouterKey} = {
          inherit (cfg.routing.openRouter) sopsFile;
          key = openRouterKey;
        };
      };

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
      description = "Call a speaker, opening a spoken conversation, whenever the owner's answer is needed now: a question, a choice, a confirmation, or news that calls for a reaction. A Home Assistant announcement is for a notice that needs no reply.";
      text = ''
        When something needs the owner's answer now, call a speaker: a
        question that blocks your work, a choice or a confirmation, or news
        they will want to react to, such as a power outage, a visitor or a
        failure that needs a decision. A Home Assistant announcement is for a
        notice that needs no reply; Telegram is for anything that can wait or
        carries detail. A call interrupts whoever is in the room, so keep it
        for what matters now.

        The speakers, by area: ${
          lib.concatStringsSep ", " (map (host: host.voiceArea) (lib.attrValues voicePes))
        }.
        To call one:

            voice-broker-call --socket ${callSocket} <Area> "<what to tell the owner>"

        The speaker chimes, says the opening in its own words, then listens;
        the owner's reply reaches you as a turn of this session, like anything
        said at a speaker, so carry on from there. The command prints
        `started` once the speaker has picked up, or `failed: <reason>` when
        the speaker is muted, in a conversation, or unreachable; then write to
        Telegram instead. Keep the opening to one or two spoken sentences;
        details can follow once the owner engages.
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
          ++ lib.optional jevRouting "${openRouterKey}:${config.sops.secrets.${sopsName openRouterKey}.path}"
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
