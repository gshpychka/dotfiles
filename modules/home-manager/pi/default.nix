{
  config,
  lib,
  pkgs,
  osConfig,
  inputs,
  ...
}:
let
  cfg = config.my.pi;
in
{
  imports = [ inputs.pituitary.homeManagerModules.default ];

  options.my.pi = {
    enable = lib.mkEnableOption "pi coding agent";
    pituitary.enable = lib.mkEnableOption "pituitary, the OpenTUI frontend for pi";
  };

  config = lib.mkIf cfg.enable {
    programs.pituitary.enable = cfg.pituitary.enable;

    programs.pi-coding-agent = {
      enable = true;
      # llm-agents.nix tracks pi releases closely; nixpkgs lags
      package = pkgs.pi;

      # store-owned: pi's own writes via /settings, `pi install`, and `pi config` are dropped
      settings = {
        defaultProvider = "anthropic";
        defaultModel = "claude-opus-5";
        defaultThinkingLevel = "medium";
        warnings.anthropicExtraUsage = false;
        theme = "gruvbox-dark";
        packages = with pkgs.piPackages.sources; [
          pi-lens
          pi-mcp-adapter
          pi-web-access
          pi-subagents
          pi-plan-mode
          pi-rewind
          pi-permission-system
          pi-todo
          pi-ask-user-question
          pi-statusline
        ];
        # resource paths rather than symlinks under configDir, which packages
        # write into: pi-permission-system keeps its logs in extensions/
        extensions = [ "${./config/extensions}" ];
        prompts = [ "${./config/prompts}" ];
        themes = [ "${./config/themes}" ];
        # ctrl+P cycles through these
        enabledModels = [
          "anthropic/*"
          "openai-codex/*" # ChatGPT subscription
          "ollama/*"
        ];
      };

      keybindings = {
        "app.session.new" = "alt+n";
        "app.session.resume" = "alt+r";
        "app.session.fork" = "alt+f";
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
  };
}
