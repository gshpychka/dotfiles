# OpenAI voice broker for the Voice PEs (packages/realtime-voice).
# The device side lives in scripts/voice-pe/; scripts/voice-pe/runbook.md has
# the setup steps that can't be declared here.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = 10310;
  voicePes = lib.filterAttrs (_: host: host.voiceArea != null) config.my.hosts;
  ha = "http://homeassistant.${config.my.domain}";

  # Flip on while tuning barge-in: every conversation's mic, echo reference and
  # echo-cancelled audio lands in /var/lib/realtime-voice/recordings. That is
  # household audio, so leave it off otherwise.
  record = true;
  # The daily systemd-tmpfiles-clean deletes recordings older than this, whether or not record is on.
  recordingRetention = "7d";
  stateDirectory = "realtime-voice";
  recordingsDir = "${stateDirectory}/recordings";

  # Keys in secrets/reaper/realtime-voice.yaml, handed to the service as
  # systemd credentials under the same names.
  credentials = lib.genAttrs [
    "openai-api-key"
    "device-token"
    "ha-token"
  ] (name: "/run/credentials/realtime-voice.service/${name}");
  # sops-nix secret names are host-global, so they carry the service name
  sopsName = name: "realtime-voice/${name}";

  settings = {
    listen_host = "0.0.0.0";
    listen_port = port;
    device_token_file = credentials.device-token;
    devices = lib.mapAttrsToList (name: host: {
      inherit name;
      address = host.lanIp;
      area = host.voiceArea;
    }) voicePes;
    openai_api_key_file = credentials.openai-api-key;
    # Each conversation runs on one of these two backends.
    realtime = {
      model = "gpt-realtime-2.1";
      voice = "marin";
      instructions = ''
        You are a voice assistant in a home, speaking through a small speaker.
        Keep answers short and conversational; never read out lists,
        IDs or markup. You can control and inspect the home through the home__
        tools. Confirm out loud what you changed. If you are interrupted, stop
        and listen.
      '';
      turn_eagerness = "high";
      transcription_model = "gpt-transcribe";
      vad_model = "${pkgs.realtime-voice.vadModel}";
      barge_in = {
        vad_threshold = 0.6;
        min_speech_ms = 192;
        min_level_dbfs = -45;
        preroll_ms = 400;
      };
    };
    live = {
      model = "gpt-live-1";
      voice = "marin";
      # Structured per https://developers.openai.com/api/docs/guides/live-prompting
      instructions = ''
        You are a voice assistant in a home, speaking through a small speaker.
        Speak warmly and naturally, in one or two short sentences. Never
        read out lists, IDs or markup.

        Backchannel policy: Use moderate backchannels. Acknowledge naturally
        without competing with the main response.

        Interruption policy: Stop speaking when the user interrupts. Listen to
        what they say.

        Delegation policy:
        Backend tools:
        - Home control: read and change lights, climate, media, sensors and
          anything else exposed in Home Assistant, and run its voice scripts.

        Delegate to the backend when:
        - The user asks about the state of the home or asks to change it.
        - A correction changes the work already requested.

        Do not delegate to the backend when:
        - You can answer from the conversation or a still-current result.
        - You need a brief clarification to understand the request.

        Delegate before giving an answer that depends on backend work.
        Do not guess the result while waiting.
      '';
      delegation = {
        model = "gpt-6-luna";
        instructions = ''
          You carry out requests for a voice assistant in one home. Use
          the home__ tools to inspect and control the home. Check the current state before changing something when the request is
          ambiguous. Report the outcome in one short plain sentence that can be
          spoken aloud: what you changed or found, with no IDs, lists or markup.
        '';
        reasoning_effort = "none";
      };
    };
    idle_timeout_s = 8;
    max_conversation_s = 600;
    recordings_dir = if record then "/var/lib/${recordingsDir}" else null;
    mcp_servers = [
      {
        # HA's built-in MCP Server integration: the Assist API over exposed entities
        name = "home";
        transport = {
          type = "http";
          url = "${ha}:8123/api/mcp";
          headers.Authorization = {
            file = credentials.ha-token;
            prefix = "Bearer ";
          };
        };
      }
    ];
  };
in
{
  sops.secrets = lib.mapAttrs' (
    name: _:
    lib.nameValuePair (sopsName name) {
      sopsFile = ../../secrets/reaper/realtime-voice.yaml;
      key = name;
    }
  ) credentials;

  systemd.services.realtime-voice = {
    description = "OpenAI Realtime voice broker";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.realtime-voice} --config ${pkgs.writeText "realtime-voice.json" (builtins.toJSON settings)}";
      LoadCredential = lib.mapAttrsToList (
        name: _: "${name}:${config.sops.secrets.${sopsName name}.path}"
      ) credentials;
      DynamicUser = true;
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

  # DynamicUser state lives under /var/lib/private; /var/lib/${stateDirectory} is a symlink to it.
  systemd.tmpfiles.settings.realtime-voice."/var/lib/private/${recordingsDir}".e.age =
    recordingRetention;

  # extraInputRules take effect only with the nftables firewall
  networking.nftables.enable = true;
  # Only the Voice PEs may open conversations: every one is billed to the OpenAI key.
  networking.firewall.extraInputRules = lib.optionalString (voicePes != { }) ''
    ip saddr { ${
      lib.concatMapStringsSep ", " (host: host.lanIp) (lib.attrValues voicePes)
    } } tcp dport ${toString port} accept
  '';
}
