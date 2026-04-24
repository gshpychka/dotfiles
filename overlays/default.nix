inputs: [
  (import ./llm-agents.nix inputs)
  (import ./direnv.nix)
  (final: prev: import ../packages { pkgs = prev; })
  inputs.mcp-servers-nix.overlays.default
]
