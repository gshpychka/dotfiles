inputs: [
  (import ./llm-agents.nix inputs)
  (final: prev: import ../packages { pkgs = prev; })
  inputs.mcp-servers-nix.overlays.default
  (import ./claude-code.nix inputs)
  (import ./claudecode-nvim.nix)
  (import ./btop.nix)
]
