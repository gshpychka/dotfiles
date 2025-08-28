inputs: [
  (import ./claude-code.nix)
  (import ./claudecode-nvim.nix)
  (import ./open-webui.nix inputs)
  (final: prev: import ../packages { pkgs = prev; })
  inputs.mcp-servers-nix.overlays.default
]
