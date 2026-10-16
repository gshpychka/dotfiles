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
  gw = config.services.openclaw-gateway;
  json = pkgs.formats.json { };
  voicePes = lib.filterAttrs (_: host: host.voiceArea != null) config.my.hosts;
  voicePeIps = map (host: host.lanIp) (lib.attrValues voicePes);
  nftables = config.networking.firewall.backend == "nftables";

  gated = cfg.mode == "gated";
  parallel = cfg.mode == "parallel";

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
  # The classifier in use: gating in gated mode, shadowing in parallel mode, or none.
  classifier =
    if gated then
      cfg.routing
    else if parallel && cfg.homeAssistant.shadow.enable then
      cfg.homeAssistant.shadow
    else
      null;
  # The OpenRouter key, only while Jev classifies: Decisions needs none.
  jevClassifies = classifier != null && classifier.provider == "jev";
  openRouterKey = "openrouter-api-key";
  # The JSON both classifier roles share (config.py _provider, _timeout).
  classifierSettings =
    c:
    {
      inherit (c) provider model;
      timeout_s = c.timeoutSeconds;
    }
    // lib.optionalAttrs (c.provider == "jev") {
      api_key_file = credential openRouterKey;
    };
  # Options of a classifier, gating or shadowing; `name` is its option path, for defaults and docs.
  classifierOptions = name: role: {
    provider = lib.mkOption {
      type = lib.types.enum (lib.attrNames routingModels);
      default = "decisions";
      description = ''
        The classifier (packages/voice-broker/src/voice_broker/routing.py)
        ${role}: `decisions`, OpenAI Decisions on the broker's OpenAI key; or
        `jev`, TypeSafe Jev through OpenRouter's System One API, on the
        OpenRouter key of `openRouter.sopsFile`. One call per request either
        way; a failure never falls back to the other.
      '';
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = routingModels.${(lib.getAttrFromPath name cfg).provider};
      defaultText = lib.literalMD "per provider: `gpt-6-luna` for decisions, `typesafe/jev-1.13` for jev";
      description = "The provider's model.";
    };
  };

  # The agent a /v1/responses request runs as, with that agent's tools, is its
  # session key's `agent:<id>:` prefix (gateway/openai-compatible-agent-run.ts at
  # e178c39e), so these keys are what make consults run as the voice agent. The
  # broker also names the agent (x-openclaw-agent-id): with two explicit agents
  # the gateway refuses a request that names none (gateway/http-utils.ts).
  voiceSessionKey = "agent:${cfg.agent.id}:main";
  observerSessionKey = "agent:${cfg.agent.id}:observer";
  # The agent of my.openclaw.mainSessionKey, agent:main:main.
  mainAgent = "main";
  # Channels the gateway runs: every one is main's, as before the voice agent.
  enabledChannels = lib.attrNames (
    lib.filterAttrs (_: channel: channel.enabled or true) (gw.config.channels or { })
  );

  # The voice agent's tools: an allowlist, so a tool added later, an MCP tool
  # included, stays out until named here. Home Assistant's own tools never
  # are, apart from read-only ones added per host: Home Assistant alone acts
  # on the home, hearing the speech itself (packages/voice-broker/src/voice_broker/assist.py).
  # Each only reads: web_fetch is GET-only and its SSRF guard refuses private and
  # loopback addresses, Home Assistant's included (tools/web-fetch.ts, infra/net/ssrf.ts).
  # The policy was checked with the gateway's own compiled matcher on the evaluated
  # config (workspace tmp/parallel-ha-audit-20261017/policy-check.mjs).
  agentAllow = [
    "web_search"
    "web_fetch"
    "memory_search"
    "memory_get"
  ]
  ++ cfg.agent.allow;
  # Denied as well, against an allowlist entry that would match them: deny
  # always wins (src/agents/tool-policy-match.ts). Each is a way to act beyond
  # a spoken answer, or to reach the credentials in the gateway's environment:
  # commands and code, the gateway and its plugins and config, other agents
  # and sessions, files, devices and the host's NixOS control. session_status
  # among them: it takes another session's key and sets that session's model,
  # main's Telegram session included (agents/tools/session-status-tool.ts).
  # Plugins' mutating tools are named too, but never `group:plugins`: that
  # would take memory_* and every MCP tool, GetLiveContext included.
  agentDeny = [
    "session_status"
    "automations"
    "file_write"
    "codex_session_send"
    "codex_session_interrupt"
    "github_publish"
    "skill_workshop"
    "wiki_apply"
    "workboard_*"
    "exec"
    "process"
    "code_execution"
    "terminal"
    "secrets"
    "gateway"
    "plugins"
    "openclaw"
    "nodes"
    "computer"
    "browser"
    "sessions_spawn"
    "subagents"
    "sessions_send"
    "sessions_history"
    "conversations_send"
    "conversations_turn"
    "agents_wait"
    "message"
    "read"
    "write"
    "edit"
    "apply_patch"
    "nixos_control"
  ]
  ++ cfg.agent.deny;
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

    mode = lib.mkOption {
      type = lib.types.enum [
        "consult"
        "gated"
        "parallel"
      ];
      default = "consult";
      description = ''
        Who handles a delegated request, and who acts on the home
        (packages/voice-broker/src/voice_broker/config.py):
        - `consult`: OpenClaw's main agent answers every delegated request.
        - `gated`: a classifier (`routing`) sends each one to Home Assistant's
          conversation agent or to OpenClaw's main agent, never both.
        - `parallel`: Home Assistant hears every utterance on its own
          pipeline (`homeAssistant.pipeline`) and alone acts on the home;
          delegated requests go to the dedicated `agent`, which can't. No
          classifier gates anything.
        Gated and parallel need homeAssistantDeviceId on every Voice PE.
      '';
    };

    openRouter.sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "SOPS file holding the flat key ${openRouterKey}, read only while a jev classifier runs.";
    };

    routing = classifierOptions [ "routing" ] "that gates each delegated request in gated mode" // {
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

    homeAssistant = {
      pipeline = lib.mkOption {
        type = lib.types.str;
        description = ''
          Parallel mode: name of the Assist pipeline that hears every
          utterance, beside GPT-Live, and alone acts on the home: its speech
          recognition and a home-only conversation agent. The broker resolves
          it by name at each conversation; scripts/voice-pe/runbook.md creates it.
        '';
      };
      readOnlyTools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        # helpers/llm.py and the integrations' llm.py at 2026.10.1: the Assist API's tools that only read
        default = [
          "GetLiveContext"
          "GetDateTime"
          "get_events"
          "get_items"
          "search_media"
          "HassTimerStatus"
        ];
        description = "Names, after the last `__`, of the agent's tools that only read the home: using them alone is answering, not acting.";
      };
      nonHomeTools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Names of exposed tools whose work is not about the home: their use is no evidence that the speech was a home request.";
      };
      shadow = {
        enable = lib.mkEnableOption ''
          classifying each delegation in parallel mode too, logged beside
          what Home Assistant actually did and never acted on. Each
          classification is a paid request'';
      }
      // classifierOptions [
        "homeAssistant"
        "shadow"
      ] "that only shadows each delegation in parallel mode"
      // {
        timeoutSeconds = lib.mkOption {
          # The bounds are config.py's MIN_ROUTING_TIMEOUT_S and MAX_ROUTING_TIMEOUT_S.
          type = lib.types.numbers.between 3 30;
          default = 4;
          description = "Time limit of a shadow classification; it only bounds a background request.";
        };
      };
    };

    agent = {
      id = lib.mkOption {
        type = lib.types.str;
        default = "voice";
        description = "Parallel mode: the OpenClaw agent consults and observations run as, the main agent's assistant without its home-action and escape tools.";
      };
      allow = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Tools the voice agent gets beyond the module's own read-only, non-home set, such as an MCP server's read-only tools.";
      };
      deny = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Tools denied beyond the module's own list; a pattern ending in `*` keeps a whole MCP server away.";
      };
    };

    observer.enable = lib.mkEnableOption ''
      in parallel mode, a read-only check, after each Home Assistant action,
      that the home matches the request. It runs off the critical path as a
      turn of the voice agent, only for turns with action evidence, and only a
      discrepancy is told; a fix goes back to Home Assistant through the user.
      Each check is an agent turn'';

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
        timeouts. The listener, credentials, devices, recordings, calls, the
        mode's settings and the gateway's address and session come from this module.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = openclaw.enable && openclaw.responsesEndpoint.enable;
            message = "my.voice-broker hands delegated work to OpenClaw on this host; enable my.openclaw and its responsesEndpoint.";
          }
          {
            assertion =
              cfg.mode == "consult"
              || lib.all (host: host.homeAssistantDeviceId != null) (lib.attrValues voicePes);
            message = "my.voice-broker.mode ${cfg.mode} runs each Voice PE's home requests or speech as that device; set my.hosts.<name>.homeAssistantDeviceId for every one.";
          }
          {
            # Each provider's API takes only its own models; another's fails every request at runtime.
            assertion =
              classifier == null
              || (
                if classifier.provider == "jev" then
                  lib.hasPrefix "typesafe/jev-" classifier.model
                else
                  !lib.hasInfix "/" classifier.model
              );
            message = "my.voice-broker's classifier model ${toString (classifier.model or "")} is not a ${
              toString (classifier.provider or "")
            } model.";
          }
          {
            assertion = !jevClassifies || cfg.openRouter.sopsFile != null;
            message = "my.voice-broker's jev classifier runs on OpenRouter; set my.voice-broker.openRouter.sopsFile.";
          }
          {
            assertion = !cfg.observer.enable || parallel;
            message = "my.voice-broker.observer checks Home Assistant's own actions, which only parallel mode has.";
          }
          {
            assertion = !cfg.homeAssistant.shadow.enable || parallel;
            message = "my.voice-broker.homeAssistant.shadow shadows parallel mode; gated mode's classifier is my.voice-broker.routing.";
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
          recordings_dir = if cfg.recordings.enable then "/var/lib/${recordingsDir}" else null;
          openclaw = {
            url = openclaw.localUrl;
            token_file = credential openclawCredential;
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
          // lib.optionalAttrs jevClassifies {
            ${sopsName openRouterKey} = {
              inherit (cfg.openRouter) sopsFile;
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

          ''
          + (
            if parallel then
              ''
                The speaker chimes, says the opening in its own words, then listens.
                The owner's reply goes to the voice agent, session ${voiceSessionKey},
                not to this session: read its outcome there with sessions_history. Home
                Assistant hears the reply too and alone carries out anything in it
                about the home. The command prints
              ''
            else
              ''
                The speaker chimes, says the opening in its own words, then listens;
                the owner's reply reaches you as a turn of this session, like anything
                said at a speaker, so carry on from there. The command prints
              ''
          )
          + ''
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
              ++ lib.optional jevClassifies "${openRouterKey}:${
                config.sops.secrets.${sopsName openRouterKey}.path
              }"
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
      }

      # Consult and gated: consults are turns of main's own session, with main's tools, as before parallel mode.
      (lib.mkIf (!parallel) {
        my.voice-broker.settings.openclaw.session_key = openclaw.mainSessionKey;
      })

      (lib.mkIf gated {
        my.voice-broker.settings.routing = classifierSettings cfg.routing // {
          inherit (cfg.routing) pipeline;
          pending_question_s = cfg.routing.pendingQuestionSeconds;
          settle_s = cfg.routing.settleSeconds;
        };
      })

      (lib.mkIf parallel {
        assertions = [
          {
            assertion = openclaw.mainSessionKey == "agent:${mainAgent}:main";
            message = "my.voice-broker pins main as the owner of every gateway surface; my.openclaw.mainSessionKey names another agent.";
          }
          {
            assertion = enabledChannels != [ ];
            message = "my.voice-broker binds the gateway's channels to main, and found none enabled.";
          }
          {
            assertion = cfg.agent.id != mainAgent;
            message = "my.voice-broker.agent must be its own agent: main has the home-action tools the voice agent is denied.";
          }
        ];

        my.voice-broker.settings = {
          home_assistant = {
            inherit (cfg.homeAssistant) pipeline;
            read_only_tools = cfg.homeAssistant.readOnlyTools;
            non_home_tools = cfg.homeAssistant.nonHomeTools;
            shadow = lib.mkIf cfg.homeAssistant.shadow.enable (classifierSettings cfg.homeAssistant.shadow);
          };
          openclaw = {
            # Named on each request too: with two agents the gateway has no default agent to fall back on.
            agent = cfg.agent.id;
            session_key = voiceSessionKey;
            # The voice starts with the main agent's conversation, as before the voice agent existed.
            history_session_key = openclaw.mainSessionKey;
            observer_session_key = lib.mkIf cfg.observer.enable observerSessionKey;
          };
        };

        # A second agent makes the roster multi-agent, which OpenClaw only accepts
        # with explicit ownership: a `default = true` marker fails `config validate`
        # ("Legacy agents.entries default markers need explicit surface owners").
        # This is what `openclaw doctor --fix` writes for that marker on main
        # (src/commands/doctor/shared/legacy-config-migrations.runtime.entries.ts,
        # src/config/legacy.default-agent-roles.ts at e178c39e), so every surface
        # main owned implicitly stays main's:
        # - its workspace, pinned (unpinned, an agent's is <defaults.workspace>/<id>)
        # - every enabled channel, Telegram included, as a binding
        # - the system agent, which runs agent-less cron jobs and owns workspace plugins
        # - the session store, and talk
        # Heartbeat and auth inheritance need no owner here: agents.defaults sets
        # heartbeat, and auth inheritance is only recorded for an owner other than main.
        services.openclaw-gateway.config = {
          agents = {
            ownership = "explicit";
            defaults = {
              systemAgent.agentId = mainAgent;
              sessionStore.agentId = mainAgent;
            };
            entries = {
              ${mainAgent}.workspace = openclaw.workspace;
              ${cfg.agent.id} = {
                # main's workspace, read-only to it (no read/write tools): its
                # identity, and its notes for memory_search, without a workspace of its own
                inherit (openclaw) workspace;
                tools = {
                  allow = agentAllow;
                  deny = agentDeny;
                  # Code mode is on by default ("auto") for the agents' model, gpt-6.1-sol, and
                  # gives the model a JavaScript exec of its own that `deny` doesn't remove. It
                  # runs in a Node vm, which is no security sandbox
                  # (src/agents/harness/tool-surface-bridge.ts, config/schema.help.runtime.ts at e178c39e).
                  codeMode = false;
                };
                # no delegation to other agents, whose tools would be theirs
                subagents.allowAgents = [ ];
              };
            };
          };
          bindings = map (channel: {
            agentId = mainAgent;
            match = {
              inherit channel;
              accountId = "*";
            };
          }) enabledChannels;
          talk.agentId = mainAgent;
        };
      })
    ]
  );
}
