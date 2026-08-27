{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.my.pi;
  configDir = "${config.xdg.configHome}/pi/agent";
in
{
  options.my.pi = {
    enable = lib.mkEnableOption "pi coding agent";
  };

  config = lib.mkIf cfg.enable {
    programs.pi-coding-agent = {
      enable = true;
      # llm-agents.nix tracks pi releases closely; nixpkgs lags
      package = pkgs.pi;
      inherit configDir;

      # store-owned: pi's own writes via /settings, `pi install`, and `pi config` are dropped
      settings = {
        defaultProvider = "anthropic";
        defaultModel = "claude-opus-5";
        defaultThinkingLevel = "medium";
        theme = "gruvbox-dark";
        # conversations are state; configDir holds credentials, trust decisions, and caches
        sessionDir = "${config.xdg.stateHome}/pi/sessions";
        # ctrl+P cycles through these
        enabledModels = [
          "anthropic/claude-opus-5"
          "anthropic/claude-sonnet-5"
          "openai-codex/*" # ChatGPT subscription
          "openai/gpt-5.4*" # OPENAI_API_KEY
          "ollama/*"
        ];
      };

      # pi ships no bindings for these session actions
      keybindings = {
        "app.session.new" = "alt+n";
        "app.session.resume" = "alt+r";
        "app.session.tree" = "alt+t";
      };

      models.providers.ollama = {
        baseUrl = osConfig.my.ollama.baseUrl;
        api = "openai-completions";
        # ollama ignores the key; pi hides models from providers with no credential
        apiKey = "ollama";
        compat = {
          supportsDeveloperRole = false;
          supportsReasoningEffort = false;
        };
        models = [
          { id = "qwen3.5:9b-q8_0"; }
          { id = "qwen3.8:27b-mtp-q4_K_M"; }
        ];
      };

      context = ./config/AGENTS.md;
    };

    # convention directories pi discovers under configDir
    home.file = {
      "${configDir}/extensions".source = ./config/extensions;
      "${configDir}/prompts".source = ./config/prompts;
      "${configDir}/themes".source = ./config/themes;
    };
  };
}
