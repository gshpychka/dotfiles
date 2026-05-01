inputs: [
  (import ./llm-agents.nix inputs)
  (final: prev: import ../packages { pkgs = prev; })
  inputs.mcp-servers-nix.overlays.default
]
