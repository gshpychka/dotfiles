inputs: [
  (import ./claude-code.nix)
  (import ./vim-plugins.nix)
  inputs.mcp-servers-nix.overlays.default
]