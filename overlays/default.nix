inputs: [
  (import ./llm-agents.nix inputs)
  (_final: prev: import ../packages { pkgs = prev; })
  (import ./tmux.nix)
  inputs.mcp-servers-nix.overlays.default
]
