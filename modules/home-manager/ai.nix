{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.ai;
in
{
  options.my.ai = {
    enable = lib.mkEnableOption "AI tools and assistants";
  };

  config = lib.mkIf cfg.enable {
    # AI CLI/TUI tools from github:numtide/llm-agents.nix (via overlay)
    # context7-mcp is from github:natsukium/mcp-servers-nix
    home.packages = with pkgs; [
      claude-code
      # until I figure out how to wire it up declaratively, add it imperatively:
      # `claude mcp add context7 -s user context7-mcp`
      # https://github.com/natsukium/mcp-servers-nix/issues/71
      # https://github.com/search?q=mcp-servers-nix+claude-code&type=code
      # https://github.com/anthropics/claude-code/issues/1455
      context7-mcp
      ccusage
      codex
      # disabling due to https://github.com/numtide/llm-agents.nix/issues/1707
      # gemini-cli
      opencode
      amp
    ];
  };
}
