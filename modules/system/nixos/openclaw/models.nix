# The models the agent's turns and its memory search call, and the
# credentials those calls use.
#
# Imperative, one-time per authOrder profile: sign in on the host:
#   openclaw models auth login --provider <provider> --device-code --profile-id <id>
{ config, lib, ... }:
let
  cfg = config.my.openclaw;
  # the provider half of the primary's provider/model
  provider = lib.head (lib.splitString "/" cfg.model.primary);
in
{
  options.my.openclaw = {
    model = {
      primary = lib.mkOption {
        type = lib.types.strMatching "[^/]+/.+";
        example = "openai/gpt-6-astra";
        description = "Default model of the agent's turns, as provider/model.";
      };
      authOrder = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        example = {
          openai = [ "openai:chatgpt" ];
        };
        description = "Auth profile ids model calls try, in order, by provider.";
      };
    };

    memorySearch.apiKey = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
      default = null;
      example = lib.literalExpression "config.my.openclaw.secretRefs.OPENAI_API_KEY";
      description = "SecretRef of the API key memory search embeds with, one of secretRefs; null leaves the embedding credential to OpenClaw's auth lookup.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.openclaw-gateway.config = {
          agents.defaults = {
            model.primary = cfg.model.primary;
            # OpenAI models default to the Codex harness; the agent's turns run on OpenClaw's own runtime
            models."openai/*".agentRuntime.id = "openclaw";
            # models a session may switch to: any of the primary's provider
            modelPolicy.allow = [ "${provider}/*" ];
          };
          auth.order = cfg.model.authOrder;
          # the model catalog stays the package's own
          models.catalogRefresh.enabled = false;
        };
      }
      (lib.mkIf (cfg.memorySearch.apiKey != null) {
        services.openclaw-gateway.config.memory.search.remote.apiKey = cfg.memorySearch.apiKey;
      })
    ]
  );
}
