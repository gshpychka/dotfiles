inputs: [
  (import ./nix-ai-tools.nix inputs)
  (final: prev: import ../packages { pkgs = prev; })
  inputs.mcp-servers-nix.overlays.default
  (import ./claude-code.nix inputs)
  (import ./claudecode-nvim.nix)
]
