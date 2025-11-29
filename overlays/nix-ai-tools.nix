# Bring in packages from github:numtide/nix-ai-tools
# These replace the nixpkgs versions for AI CLI/TUI tools
inputs: final: prev:
let
  ai-tools = inputs.nix-ai-tools.packages.${prev.system};
in
{
  inherit (ai-tools)
    amp
    ccusage
    codex
    gemini-cli
    opencode
    ;
}
