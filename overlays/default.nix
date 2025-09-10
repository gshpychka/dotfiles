inputs: [
  (import ./claude-code.nix)
  (import ./claudecode-nvim.nix)
  (final: prev: import ../packages { pkgs = prev; })
  inputs.mcp-servers-nix.overlays.default
]
