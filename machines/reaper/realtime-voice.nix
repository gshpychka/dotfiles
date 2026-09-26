# OpenAI Realtime voice broker for the kitchen Voice PE (packages/realtime-voice).
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
  device = config.my.hosts.kitchen-assistant;
  ha = "http://homeassistant.${config.my.domain}";

  # Flip on while tuning barge-in: every conversation's mic, echo reference and
  # echo-cancelled audio lands in /var/lib/realtime-voice/recordings. That is
  # household audio, so leave it off otherwise.
  record = false;

  # Keys in secrets/reaper/realtime-voice.yaml, handed to the service as
  # systemd credentials under the same names.
  credentials = lib.genAttrs [
    "openai-api-key"
    "device-token"
    "ha-token"
    "ha-mcp-url"
  ] (name: "/run/credentials/realtime-voice.service/${name}");
  # sops-nix secret names are host-global, so they carry the service name
  sopsName = name: "realtime-voice/${name}";

  settings = {
    listen_host = "0.0.0.0";
    listen_port = port;
    device_token_file = credentials.device-token;
    openai_api_key_file = credentials.openai-api-key;
    model = "gpt-realtime-2.1";
    voice = "marin";
    instructions = ''
      You are the voice assistant in a home kitchen, speaking through a small
      speaker. Keep answers short and conversational; never read out lists,
      IDs or markup. You can control and inspect the home through the home__
      tools, and administer Home Assistant (automations, scripts, helpers,
      dashboards) through the admin__ tools. Confirm out loud what you changed.
      If you are interrupted, stop and listen.
    '';
    transcription_model = null;
    vad_model = "${pkgs.realtime-voice.vadModel}";
    barge_in = {
      vad_threshold = 0.6;
      min_speech_ms = 192;
      min_level_dbfs = -45;
      preroll_ms = 400;
    };
    idle_timeout_s = 8;
    max_conversation_s = 600;
    recordings_dir = if record then "/var/lib/realtime-voice/recordings" else null;
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
      {
        # The ha-mcp add-on; its URL path is the credential
        name = "admin";
        transport = {
          type = "http";
          url.file = credentials.ha-mcp-url;
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
      StateDirectory = "realtime-voice";
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

  # Only the Voice PE may open conversations: every one is billed to the OpenAI key.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp --dport ${toString port} -s ${device.lanIp} -j nixos-fw-accept
  '';
}
