# OpenClaw personal-assistant gateway (https://docs.openclaw.ai), built on the
# nix-openclaw NixOS module (services.openclaw-gateway).
#
# Trust boundaries:
#   - the gateway runs as its own system user and reads secrets from files
#     rendered by sops; the world-readable openclaw.json carries only env
#     references;
#   - agent tool execution (exec, read, write, ...) runs in rootless Podman
#     containers owned by that user, with no network and only the workspace.
#
# Imperative, one-time without trustedProxy: a browser reaching the Control UI
# through a reverse proxy is a remote device and must be paired from the host:
#   openclaw devices list / openclaw devices approve <id>
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  inherit (pkgs.stdenv.hostPlatform) system;
  podman = config.virtualisation.podman.package;

  configEtcPath = lib.removePrefix "/etc/" gw.configPath;
  configFile = config.environment.etc.${configEtcPath}.source;
  unit = "${gw.unitName}.service";

  sopsKey = key: "openclaw/${key}";
  placeholder = name: config.sops.placeholder.${name};

  # Rootless Podman under a system service has no user session: runtime state
  # goes to the unit's RuntimeDirectory, and the cgroupfs manager stands in for
  # the systemd one, which needs a user D-Bus.
  runtimeDir = "/run/${gw.unitName}";
  containersConf = (pkgs.formats.toml { }).generate "openclaw-containers.conf" {
    engine = {
      cgroup_manager = "cgroupfs";
      events_logger = "file";
    };
  };

  # Tool-execution image. With no tag given, dockerTools tags the image with
  # its output hash, so each content change yields a new immutable reference.
  sandboxImage = pkgs.dockerTools.buildLayeredImage {
    name = "openclaw-sandbox";
    contents = with pkgs; [
      bashInteractive
      coreutils
      findutils
      diffutils
      gnugrep
      gnused
      gawk
      gnutar
      gzip
      curl
      git
      jq
      ripgrep
      # the sandbox filesystem bridge runs python3 from /bin
      python3
      cacert
      dockerTools.fakeNss
    ];
    extraCommands = ''
      mkdir -p tmp
      chmod 1777 tmp
    '';
    config = {
      Cmd = [
        "sleep"
        "infinity"
      ];
      Env = [
        "PATH=/bin"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      ];
    };
  };
  sandboxRepository = "localhost/${sandboxImage.imageName}";
  sandboxImageRef = "${sandboxRepository}:${sandboxImage.imageTag}";

  # Loads the current image into the gateway user's store and drops earlier
  # tags and their containers.
  loadSandboxImage = pkgs.writeShellScript "openclaw-load-sandbox-image" ''
    set -euo pipefail
    ${lib.getExe podman} load --quiet --input ${sandboxImage}
    ${lib.getExe podman} images --format '{{.Repository}}:{{.Tag}}' \
        --filter reference=${sandboxRepository} \
      | { grep -vxF ${sandboxImageRef} || true; } \
      | xargs --no-run-if-empty ${lib.getExe podman} rmi --force
  '';

  enabledMcpServers = lib.filterAttrs (_: server: server.enable) cfg.mcpServers;
  mcpSecrets = lib.concatMapAttrs (_: server: server.secrets) enabledMcpServers;

  # the variable OpenClaw's clients read for the shared secret in each auth mode
  gatewaySecretVar =
    if cfg.trustedProxy.enable then "OPENCLAW_GATEWAY_PASSWORD" else "OPENCLAW_GATEWAY_TOKEN";
  # Variables the gateway resolves from its environment file, each mapped to
  # its key in cfg.sopsFile; openclaw.json references them as env SecretRefs or
  # ${VAR} substitutions.
  envVars = gatewayEnvVars // mcpSecrets;
  gatewayEnvVars = {
    ${gatewaySecretVar} = "gateway-token";
  }
  // lib.optionalAttrs cfg.telegram.enable {
    TELEGRAM_BOT_TOKEN = "telegram-bot-token";
    TELEGRAM_OWNER_ID = "telegram-owner-id";
  }
  // cfg.providerKeys;
  envRef = id: {
    source = "env";
    provider = "default";
    inherit id;
  };

  publicOrigin = "https://${cfg.publicHost}";

  # Environment shared by the gateway and the operator CLI.
  gatewayEnv = {
    OPENCLAW_NIX_MODE = "1";
    OPENCLAW_CONFIG_PATH = gw.configPath;
    OPENCLAW_STATE_DIR = gw.stateDir;
    OPENCLAW_DISABLE_BONJOUR = "1";
    HOME = gw.stateDir;
    XDG_RUNTIME_DIR = runtimeDir;
    CONTAINERS_CONF_OVERRIDE = "${containersConf}";
  };

  # The operator CLI, run as the gateway user with the gateway's environment.
  cli = pkgs.writeShellApplication {
    name = "openclaw";
    runtimeInputs = [ podman ];
    text = ''
      if [ "$(id -un)" != ${gw.user} ]; then
        exec sudo -u ${gw.user} -- "$0" "$@"
      fi
      # Node fails to spawn children (ffmpeg, podman) from a working directory
      # the gateway user cannot enter
      [ -x . ] || cd ${gw.stateDir}
      ${lib.toShellVars gatewayEnv}
      export ${lib.concatStringsSep " " (lib.attrNames gatewayEnv)}
      set -a
      # shellcheck disable=SC1091
      . ${config.sops.templates."openclaw.env".path}
      set +a
      exec ${lib.getExe' gw.package "openclaw"} "$@"
    '';
  };

  openclawConfig = {
    gateway = {
      mode = "local";
      bind = "loopback";
      inherit (gw) port;
      auth =
        if cfg.trustedProxy.enable then
          {
            mode = "trusted-proxy";
            # clients that bypass the proxy, such as the operator CLI
            password = envRef gatewaySecretVar;
            trustedProxy = {
              inherit (cfg.trustedProxy) userHeader;
              allowUsers = cfg.trustedProxy.users;
              # the proxy connects over loopback, so every local process that
              # can reach the port can assert an identity
              allowLoopback = true;
              deviceAutoApprove.enabled = true;
            };
            identityScopes = lib.genAttrs cfg.trustedProxy.users (_: [ "operator.admin" ]);
          }
        else
          {
            mode = "token";
            token = envRef gatewaySecretVar;
          };
      # nginx proxies the Control UI from loopback
      trustedProxies = [ "127.0.0.1" ];
      inherit publicOrigin;
      controlUi = {
        allowedOrigins = [ publicOrigin ];
        automaticallyFetchFavicons = false;
      };
      tailscale.mode = "off";
    };
    discovery.mdns.mode = "off";
    browser.enabled = false;
    acp.enabled = false;

    plugins.entries.telegram.enabled = cfg.telegram.enable;
    channels = lib.optionalAttrs cfg.telegram.enable {
      telegram = {
        enabled = true;
        botToken = envRef "TELEGRAM_BOT_TOKEN";
        dmPolicy = "allowlist";
        allowFrom = [ "\${TELEGRAM_OWNER_ID}" ];
        groupPolicy = "disabled";
        configWrites = false;
      };
    };
    commands = {
      ownerAllowFrom = lib.optional cfg.telegram.enable "telegram:\${TELEGRAM_OWNER_ID}";
      bash = false;
      config = false;
      mcp = false;
      plugins = false;
      restart = false;
    };

    models.catalogRefresh.enabled = false;

    agents.defaults = {
      model = {
        inherit (cfg.model) primary fallbacks;
      };
      workspace = "${gw.stateDir}/workspace";
      userTimezone = config.time.timeZone;
      heartbeat.every = "0m";
      sandbox = {
        mode = "all";
        backend = "podman";
        scope = "agent";
        workspaceAccess = "rw";
        docker = {
          image = sandboxImageRef;
          network = "none";
          readOnlyRoot = true;
          capDrop = [ "ALL" ];
        };
        browser.enabled = false;
      };
    }
    // lib.optionalAttrs (cfg.model.utility != null) {
      utilityModel = cfg.model.utility;
    };

    tools = {
      exec.host = "sandbox";
      elevated.enabled = false;
      fs.workspaceOnly = true;
      # the sandbox allowlist is the core file/exec set; MCP tools belong to
      # the bundle-mcp plugin id
      sandbox.tools.alsoAllow = [
        "bundle-mcp"
        "web_fetch"
      ];
      media = {
        # an empty model list otherwise falls through to auto-detection
        audio.enabled = cfg.transcription != [ ];
        models = cfg.transcription;
      };
    };

    mcp.servers = lib.mapAttrs (_: server: server.settings) enabledMcpServers;

    inherit (cfg) tts;
  };

  # The gateway refuses to start on unknown or legacy keys in a read-only
  # config, and reports unresolved ${VAR} references only as warnings.
  configCheck =
    pkgs.runCommand "openclaw-config-check"
      {
        nativeBuildInputs = [
          gw.package
          pkgs.jq
        ];
        env = lib.mapAttrs (_: _: "1") envVars // {
          OPENCLAW_NIX_MODE = "1";
          OPENCLAW_CONFIG_PATH = configFile;
        };
      }
      ''
        export HOME=$TMPDIR OPENCLAW_STATE_DIR=$TMPDIR/state
        openclaw config validate --json | tee $out
        jq -e '.valid and (.warnings | length == 0)' $out > /dev/null
      '';
in
{
  imports = [ inputs.nix-openclaw.nixosModules.openclaw-gateway ];

  options.my.openclaw = {
    enable = lib.mkEnableOption "the OpenClaw gateway";

    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        SOPS file holding flat keys gateway-token, plus telegram-bot-token and
        telegram-owner-id (a numeric Telegram user id) with telegram.enable,
        and every key named by providerKeys and by an enabled MCP server's
        secrets.
      '';
    };

    publicHost = lib.mkOption {
      type = lib.types.str;
      description = "HTTPS host name the Control UI is served from.";
    };

    trustedProxy = {
      enable = lib.mkEnableOption ''
        identity from the reverse proxy: requests carrying userHeader from
        gateway.trustedProxies sign in as that user, and their browsers enroll
        without pairing'';
      userHeader = lib.mkOption {
        type = lib.types.str;
        description = "Request header the proxy sets to the signed-in user's name.";
      };
      users = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        description = "Proxy-authenticated users admitted, each as an administrator.";
      };
    };

    telegram.enable = lib.mkEnableOption "the Telegram channel, answering DMs from the owner only";

    model = {
      primary = lib.mkOption {
        type = lib.types.str;
        example = "openai/gpt-6-astra";
        description = "Model answering every turn, as provider/model.";
      };
      fallbacks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Models tried in order when the primary fails, as provider/model.";
      };
      utility = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Model for short internal tasks such as titles and progress
          narration, as provider/model; null takes the primary provider's
          small model.
        '';
      };
    };

    providerKeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        OPENAI_API_KEY = "openai-api-key";
      };
      description = ''
        Provider credentials by the environment variable OpenClaw reads for
        them, each set from the named sopsFile key.
      '';
    };

    mcpServers = lib.mkOption {
      default = { };
      description = "MCP servers whose tools the agent gets, keyed by server name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether the server is connected; its secrets must exist in sopsFile while it is.";
            };
            settings = lib.mkOption {
              inherit (pkgs.formats.json { }) type;
              description = ''
                The server's mcp.servers entry (https://docs.openclaw.ai/tools/mcp),
                a url or a command. Strings reference secrets as ''${NAME}.
              '';
            };
            secrets = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              example = {
                HOME_ASSISTANT_TOKEN = "home-assistant-token";
              };
              description = "Environment variables for \${NAME} references in settings, each set from the named sopsFile key.";
            };
          };
        }
      );
    };

    tts = lib.mkOption {
      inherit (pkgs.formats.json { }) type;
      default = { };
      example = {
        provider = "elevenlabs";
        auto = "inbound";
      };
      description = "Text-to-speech settings (https://docs.openclaw.ai/tools/tts).";
    };

    transcription = lib.mkOption {
      type = lib.types.listOf (pkgs.formats.json { }).type;
      default = [ ];
      example = [
        {
          provider = "elevenlabs";
          model = "scribe_v2";
          capabilities = [ "audio" ];
        }
      ];
      description = "tools.media.models entries that transcribe inbound audio (https://docs.openclaw.ai/nodes/audio).";
    };
  };

  config = lib.mkIf cfg.enable {
    # a variable claimed twice would resolve to only one of its sops keys
    assertions =
      let
        claims =
          lib.attrNames gatewayEnvVars
          ++ lib.concatMap (server: lib.attrNames server.secrets) (lib.attrValues enabledMcpServers);
      in
      [
        {
          assertion = lib.allUnique claims;
          message = "my.openclaw.mcpServers: secret variable names must be unique and differ from the gateway's own.";
        }
      ];

    services.openclaw-gateway = {
      enable = true;
      package = inputs.nix-openclaw.packages.${system}.openclaw-gateway;
      config = openclawConfig;
      environment = gatewayEnv;
      environmentFiles = [ config.sops.templates."openclaw.env".path ];
      servicePath = [ podman ];
      execStartPre = [ "${loadSandboxImage}" ];
    };

    # only the gateway user reads its config
    environment.etc.${configEtcPath} = {
      mode = lib.mkForce "0400";
      inherit (gw) user group;
    };

    users.users.${gw.user}.autoSubUidGidRange = true;
    virtualisation.podman.enable = true;

    environment.systemPackages = [
      cli
      # media decoding resolves ffmpeg/ffprobe only from fixed system paths,
      # /run/current-system/sw/bin on NixOS, never from PATH
      pkgs.ffmpeg-headless
    ];

    systemd.services.${gw.unitName} = {
      # config changes land in /etc without touching the unit
      restartTriggers = [ configFile ];
      serviceConfig = {
        StandardOutput = lib.mkForce "journal";
        StandardError = lib.mkForce "journal";
        RuntimeDirectory = gw.unitName;
        UMask = "0077";
        # No seccomp-backed directives: systemd then implies NoNewPrivileges for
        # a non-root User= (context_has_seccomp, src/core/exec-invoke.c), and
        # rootless Podman needs the setuid newuidmap/newgidmap.
        ProtectSystem = "strict";
        ReadWritePaths = [ gw.stateDir ];
        ProtectHome = true;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        MemoryMax = "6G";
        TasksMax = 1024;
      };
    };

    sops = {
      secrets = lib.mapAttrs' (
        _: key:
        lib.nameValuePair (sopsKey key) {
          inherit (cfg) sopsFile;
          inherit key;
        }
      ) envVars;
      # owned by the gateway user, whose operator CLI reads it
      templates = {
        "openclaw.env" = {
          content = lib.concatStrings (
            lib.mapAttrsToList (var: key: "${var}=${placeholder (sopsKey key)}\n") envVars
          );
          owner = gw.user;
          restartUnits = [ unit ];
        };
      };
    };

    system.checks = [ configCheck ];
  };
}
