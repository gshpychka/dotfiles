# Native Codex app-server harness, using the existing OpenClaw ChatGPT profile.
# The pinned nix-openclaw catalog owns the plugin and its managed Codex binary;
# no imperative plugin install, global CLI, or credential file is needed.
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  cfg = config.my.openclaw;
  codexPlugin =
    inputs.nix-openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-runtime-plugin-codex;
in
{
  config = lib.mkIf cfg.enable {
    services.openclaw-gateway.config.plugins = {
      load.paths = [ codexPlugin.openclawRuntimePlugin.loadPath ];
      entries.codex = {
        enabled = true;
        config.appServer = {
          # Managed stdio bridges the ordered OpenClaw OAuth profile in memory.
          # Leave command unset so the plugin uses its own pinned binary.
          homeScope = "agent";
          clearEnv = [
            "CODEX_API_KEY"
            "OPENAI_API_KEY"
          ];
        };
      };
    };
    # Keep the default OpenClaw runtime/model and existing Claude ACPX unchanged.
    # Native Codex is selected explicitly with /codex bind in a separate chat.
  };
}
