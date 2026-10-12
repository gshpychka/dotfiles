# The models the agent thinks with, and how their calls authenticate.
{ config, lib, ... }:
let
  cfg = config.my.openclaw;
  models = [
    cfg.model.primary
  ]
  ++ cfg.model.fallbacks
  ++ lib.optional (cfg.model.utility != null) cfg.model.utility;
  providers = lib.unique (map (model: lib.head (lib.splitString "/" model)) models);
  memoryKeyVar = "MEMORY_SEARCH_API_KEY";
in
{
  options.my.openclaw = {
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

    memorySearch.apiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "openai-api-key";
      description = ''
        The sopsFile key holding the API key memory search embeds with; null
        leaves the embedding credential to OpenClaw's auth lookup.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.openclaw-gateway.config = {
        auth.order = cfg.model.authOrder;
        models.catalogRefresh.enabled = false;
        agents.defaults = {
          model = {
            inherit (cfg.model) primary fallbacks;
          };
          # In auto mode the Codex harness claims openai/* routes; the entry keeps
          # them on OpenClaw's own runtime and leaves an OpenAI sign-in nothing to
          # patch in openclaw.json, a write Nix mode refuses.
          models."openai/*".agentRuntime.id = "openclaw";
          # the models sessions may select: any of the configured providers'
          modelPolicy.allow = map (provider: "${provider}/*") providers;
        };
      };
    })
    (lib.mkIf (cfg.enable && cfg.model.utility != null) {
      services.openclaw-gateway.config.agents.defaults.utilityModel = cfg.model.utility;
    })
    (lib.mkIf (cfg.enable && cfg.memorySearch.apiKey != null) {
      my.openclaw.secrets.${memoryKeyVar} = cfg.memorySearch.apiKey;
      services.openclaw-gateway.config.memory.search.remote.apiKey = cfg.secretRefs.${memoryKeyVar};
    })
  ];
}
