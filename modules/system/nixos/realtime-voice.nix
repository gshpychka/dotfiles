# OpenAI voice broker for the Voice PEs (packages/realtime-voice).
# Setup steps that can't be declared here: scripts/voice-pe/runbook.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.realtime-voice;
  json = pkgs.formats.json { };
  voicePes = lib.filterAttrs (_: host: host.voiceArea != null) config.my.hosts;
  voicePeIps = map (host: host.lanIp) (lib.attrValues voicePes);
  nftables = config.networking.firewall.backend == "nftables";

  stateDirectory = "realtime-voice";
  recordingsDir = "${stateDirectory}/recordings";

  # sopsFile keys, handed to the service as systemd credentials under the same names.
  credentialNames = lib.unique (
    [
      "openai-api-key"
      "device-token"
    ]
    ++ lib.mapAttrsToList (_: server: server.bearerTokenKey) cfg.mcpServers
  );
  credential = name: "/run/credentials/realtime-voice.service/${name}";
  # sops-nix secret names are host-global, so they carry the service name
  sopsName = name: "realtime-voice/${name}";
in
{
  options.my.realtime-voice = {
    enable = lib.mkEnableOption "the realtime-voice broker";

    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "SOPS file holding flat keys openai-api-key, device-token and every mcpServers bearerTokenKey.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 10310;
      description = "TCP port the Voice PEs connect to.";
    };

    recordings = {
      enable = lib.mkEnableOption ''
        recording every conversation's mic, echo reference and echo-cancelled
        audio, for tuning barge-in. That is household audio, so leave it off
        otherwise'';
      retention = lib.mkOption {
        type = lib.types.str;
        default = "7d";
        description = "systemd-tmpfiles age past which recordings are deleted, whether or not recording is on.";
      };
    };

    mcpServers = lib.mkOption {
      default = { };
      description = "HTTP MCP servers whose tools both backends get as <name>__<tool>, keyed by server name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              description = "Endpoint URL.";
            };
            bearerTokenKey = lib.mkOption {
              type = lib.types.str;
              description = "sopsFile key holding the bearer token sent with every request.";
            };
          };
        }
      );
    };

    settings = lib.mkOption {
      inherit (json) type;
      default = { };
      description = ''
        Broker configuration (packages/realtime-voice/src/realtime_voice/config.py):
        the realtime and live backends and the conversation timeouts. The
        listener, credentials, devices, VAD model, recordings and MCP servers
        come from this module.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    my.realtime-voice.settings = {
      listen_host = "0.0.0.0";
      listen_port = cfg.port;
      device_token_file = credential "device-token";
      openai_api_key_file = credential "openai-api-key";
      devices = lib.mapAttrsToList (name: host: {
        inherit name;
        address = host.lanIp;
        area = host.voiceArea;
      }) voicePes;
      realtime.vad_model = "${pkgs.realtime-voice.vadModel}";
      recordings_dir = if cfg.recordings.enable then "/var/lib/${recordingsDir}" else null;
      mcp_servers = lib.mapAttrsToList (name: server: {
        inherit name;
        transport = {
          type = "http";
          inherit (server) url;
          headers.Authorization = {
            file = credential server.bearerTokenKey;
            prefix = "Bearer ";
          };
        };
      }) cfg.mcpServers;
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

    systemd.services.realtime-voice = {
      description = "OpenAI Realtime voice broker";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.realtime-voice} --config ${json.generate "realtime-voice.json" cfg.settings}";
        LoadCredential = map (
          name: "${name}:${config.sops.secrets.${sopsName name}.path}"
        ) credentialNames;
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
      cfg.recordings.retention;

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
