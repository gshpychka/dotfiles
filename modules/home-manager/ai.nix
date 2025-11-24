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
      gemini-cli-bin
      # opencode broken on darwin
      # https://github.com/sst/opencode/issues/4575
      # https://github.com/oven-sh/bun/issues/24645
      # opencode
      amp-cli
    ];
  };
}
