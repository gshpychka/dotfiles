# OpenClaw personal-assistant gateway (https://docs.openclaw.ai), built on the
# nix-openclaw NixOS module (services.openclaw-gateway).
#
# Trust boundaries:
#   - the gateway runs as its own system user and reads secrets from files
#     rendered by sops; openclaw.json carries only env references;
#   - every session runs its tools on this host as the gateway user. File tools
#     stay inside the workspace, and commands run against an allowlist
#     (hostExec.allowlist); a reviewer model runs any other command once,
#     denies it, or asks the owner in the Telegram DM. OpenClaw checks a DM's
#     sandbox policy under a per-peer key, so its non-main sandbox mode covers
#     the owner's DM as well.
#
# Imperative, one-time without trustedProxy: a browser reaching the Control UI
# through a reverse proxy is a remote device and must be paired from the host:
#   openclaw devices list / openclaw devices approve <id>
#
# Imperative, one-time: for the agent to decrypt secrets, add the public key of
# its age key (ageKeyFile) to .sops.yaml:
#   sudo grep '^# public key' /var/lib/openclaw/age-key.txt
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

  configEtcPath = lib.removePrefix "/etc/" gw.configPath;
  configFile = config.environment.etc.${configEtcPath}.source;
  unit = "${gw.unitName}.service";

  sopsKey = key: "openclaw/${key}";
  placeholder = name: config.sops.placeholder.${name};

  # the private key exists only on this host
  generateAgeKey = pkgs.writeShellScript "openclaw-generate-age-key" ''
    set -euo pipefail
    [ -e ${cfg.ageKeyFile} ] || ${lib.getExe' pkgs.age "age-keygen"} -o ${cfg.ageKeyFile}
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
  // lib.optionalAttrs (cfg.memorySearch.apiKey != null) {
    ${memorySearchKeyVar} = cfg.memorySearch.apiKey;
  }
  // cfg.providerKeys;
  memorySearchKeyVar = "MEMORY_SEARCH_API_KEY";
  envRef = id: {
    source = "env";
    provider = "default";
    inherit id;
  };

  publicOrigin = "https://${cfg.publicHost}";

  hostTools = pkgs.buildEnv {
    name = "openclaw-host-tools";
    paths = cfg.hostTools;
  };

  skillsDir = pkgs.runCommand "openclaw-skills" { } (
    lib.concatStrings (
      lib.mapAttrsToList (name: skill: ''
        mkdir -p $out/${name}
        cp ${pkgs.writeText "${name}-SKILL.md" ''
          ---
          name: ${name}
          description: ${builtins.toJSON skill.description}
          ---
          ${skill.text}''} $out/${name}/SKILL.md
      '') cfg.skills
    )
  );

  # the main session's host exec approvals, which the gateway keeps in its
  # SQLite state, outside openclaw.json
  approvalsFile = pkgs.writeText "openclaw-exec-approvals.json" (
    builtins.toJSON {
      version = 1;
      defaults = {
        security = "allowlist";
        ask = "on-miss";
        askFallback = "deny";
        autoAllowSkills = false;
      };
      agents.main.allowlist = cfg.hostExec.allowlist;
    }
  );

  # Environment shared by the gateway and the operator CLI.
  gatewayEnv = {
    OPENCLAW_NIX_MODE = "1";
    OPENCLAW_CONFIG_PATH = gw.configPath;
    OPENCLAW_STATE_DIR = gw.stateDir;
    OPENCLAW_DISABLE_BONJOUR = "1";
    HOME = gw.stateDir;
    SOPS_AGE_KEY_FILE = cfg.ageKeyFile;
  };

  # The operator CLI, run as the gateway user with the unit's environment.
  cli = pkgs.writeShellApplication {
    name = "openclaw";
    text = ''
      if [ "$(id -un)" != ${gw.user} ]; then
        exec sudo -u ${gw.user} -- "$0" "$@"
      fi
      # Node fails to spawn children (ffmpeg) from a working directory the
      # gateway user cannot enter
      [ -x . ] || cd ${gw.stateDir}
      ${lib.toShellVars gw.environment}
      export ${lib.concatStringsSep " " (lib.attrNames gw.environment)}
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
      http.endpoints.responses.enabled = cfg.responsesEndpoint.enable;
      inherit publicOrigin;
      controlUi = {
        allowedOrigins = [ publicOrigin ];
        automaticallyFetchFavicons = false;
      };
      tailscale.mode = "off";
    };
    discovery.mdns.mode = "off";
    browser.enabled = false;

    plugins.entries.telegram.enabled = cfg.telegram.enable;
    channels = lib.optionalAttrs cfg.telegram.enable {
      telegram = {
        enabled = true;
        botToken = envRef "TELEGRAM_BOT_TOKEN";
        dmPolicy = "allowlist";
        allowFrom = [ "\${TELEGRAM_OWNER_ID}" ];
        groupPolicy = "disabled";
        configWrites = false;
        # host exec approvals from the main session, as buttons in the DM
        execApprovals = {
          enabled = true;
          approvers = [ "\${TELEGRAM_OWNER_ID}" ];
          target = "dm";
        };
        capabilities.inlineButtons = "dm";
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

    auth.order = cfg.model.authOrder;

    agents.defaults = {
      model = {
        inherit (cfg.model) primary fallbacks;
      };
      # OpenClaw's own runtime, which runs host commands through
      # hostExec.allowlist; in auto mode the Codex harness claims openai/* routes.
      # The entry also leaves an OpenAI sign-in nothing to patch in openclaw.json,
      # a write Nix mode refuses.
      models."openai/*".agentRuntime.id = "openclaw";
      inherit (cfg) workspace;
      userTimezone = config.time.timeZone;
      heartbeat.every = "0m";
    }
    // lib.optionalAttrs (cfg.model.utility != null) {
      utilityModel = cfg.model.utility;
    };

    tools = {
      exec = {
        host = "gateway";
        # host commands: the allowlist runs; the reviewer model runs any other
        # command once, denies it, or asks the owner
        mode = "auto";
        reviewer = lib.filterAttrs (_: value: value != null) cfg.hostExec.reviewer;
        pathPrepend = [
          "${hostTools}/bin"
          # setuid wrappers such as sudo; OpenClaw's login-shell PATH merge
          # is best-effort
          config.security.wrapperDir
        ];
      };
      fs.workspaceOnly = true;
      media = {
        # an empty model list otherwise falls through to auto-detection
        audio.enabled = cfg.transcription != [ ];
        models = cfg.transcription;
      };
    };

    mcp.servers = lib.mapAttrs (_: server: server.settings) enabledMcpServers;

    skills.load.extraDirs = [ "${skillsDir}" ];

    inherit (cfg) tts;
  }
  // lib.optionalAttrs (cfg.memorySearch.apiKey != null) {
    memory.search.remote.apiKey = envRef memorySearchKeyVar;
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
        every key named by providerKeys and by an enabled MCP server's
        secrets, and github-app-private-key with github set.
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

    responsesEndpoint.enable = lib.mkEnableOption ''
      the OpenResponses endpoint, POST /v1/responses
      (https://docs.openclaw.ai/gateway/openresponses-http-api): one agent turn
      per request, as the owner, for any client holding the gateway secret'';

    localUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString gw.port}";
      readOnly = true;
      description = "Base URL of the gateway's HTTP endpoints on this host.";
    };

    secretFile = lib.mkOption {
      type = lib.types.str;
      default = config.sops.secrets.${sopsKey "gateway-token"}.path;
      readOnly = true;
      description = "File holding the gateway secret, the bearer credential of its HTTP endpoints; readable by root only.";
    };

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
      authOrder = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        example = {
          openai = [ "openai:chatgpt" ];
        };
        description = ''
          Auth profiles model calls try, in order, by provider; a profile
          comes from `openclaw models auth login --profile-id <id>`.
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

    memorySearch.apiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "openai-api-key";
      description = ''
        The sopsFile key holding the API key memory search embeds with; null
        leaves the embedding credential to OpenClaw's auth lookup.
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

    workspace = lib.mkOption {
      type = lib.types.str;
      default = "${gw.stateDir}/workspace";
      readOnly = true;
      description = "The agent's workspace, the only directory its file tools reach.";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${gw.stateDir}/age-key.txt";
      readOnly = true;
      description = ''
        The agent's own age key, generated on this host; sops in the agent's
        host commands decrypts with it.
      '';
    };

    hostTools = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Packages on PATH for the agent's commands.";
    };

    hostExec.allowlist = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            pattern = lib.mkOption {
              type = lib.types.str;
              example = "openclaw-rebuild";
              description = "Command name on PATH, or a glob of resolved binary paths.";
            };
            argPattern = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "^switch( |$)";
              description = ''
                ECMAScript regex the arguments, joined by single spaces, must
                match; null admits any arguments.
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        Host commands the main session runs without review
        (https://docs.openclaw.ai/tools/exec-approvals). The reviewer model
        runs any other host command once, denies it, or asks the owner.
      '';
      apply = map (lib.filterAttrs (_: value: value != null));
    };

    hostExec.reviewer = {
      model = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "openai/gpt-5.6-terra";
        description = "Model reviewing host commands outside the allowlist, as provider/model; null takes the primary.";
      };
      thinking = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "minimal"
            "low"
            "medium"
            "high"
            "xhigh"
            "max"
          ]
        );
        default = null;
        description = "Reasoning effort of the reviewer model; null takes the provider default.";
      };
    };

    skills = lib.mkOption {
      default = { };
      description = "Skills (https://docs.openclaw.ai/tools/skills) describing the agent's host commands, keyed by name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.str;
              description = "One line, under 160 characters, shown to the agent.";
            };
            text = lib.mkOption {
              type = lib.types.lines;
              description = "SKILL.md body: when and how to use the commands.";
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
    assertions =
      let
        claims =
          lib.attrNames gatewayEnvVars
          ++ lib.concatMap (server: lib.attrNames server.secrets) (lib.attrValues enabledMcpServers);
      in
      [
        {
          # a variable claimed twice would resolve to only one of its sops keys
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
      execStartPre = [
        "${generateAgeKey}"
        # non-fatal: OpenClaw's default approvals ask for every host command
        "-${lib.getExe' gw.package "openclaw"} approvals set --file ${approvalsFile}"
      ];
    };

    # only the gateway user reads its config
    environment.etc.${configEtcPath} = {
      mode = lib.mkForce "0400";
      inherit (gw) user group;
    };

    # for tmpfiles rules inside it: tmpfiles creates a missing parent as root
    systemd.tmpfiles.rules = [ "d ${cfg.workspace} 0700 ${gw.user} ${gw.group} - -" ];

    my.openclaw = {
      # sops with the agent's own key (SOPS_AGE_KEY_FILE), for secrets encrypted to it
      hostTools = with pkgs; [
        sops
        age
        git
      ];
      skills.secrets = {
        description = "Read and write sops secrets encrypted to your own age key, in a checkout of the owner's dotfiles.";
        text = ''
          `sops` decrypts with your own age key, which never leaves this host.
          In a checkout of the owner's dotfiles, files under `secrets/openclaw/`
          are encrypted to you and to the owner, and new files there get the
          right keys from `.sops.yaml`:

          - `sops decrypt secrets/openclaw/<file>` reads one;
          - `sops set secrets/openclaw/<file> '["<key>"]' '"<value>"'` adds or
            changes a value.

          A decrypted value enters your context and goes to the model
          provider: decrypt only what the task needs, and never repeat a
          secret value in a reply.
        '';
      };
    };

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
        UMask = "0077";
        # No filesystem sandboxing: host commands share this unit's mount
        # namespace, and root ones through sudo write /nix, /etc and /root.
        # No NoNewPrivileges, nor seccomp-backed directives, which imply it for
        # a non-root User= (context_has_seccomp, src/core/exec-invoke.c): sudo
        # is setuid.
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
