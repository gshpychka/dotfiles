inputs: [
  (import ./claude-code.nix)
  (import ./claudecode-nvim.nix)
  (import ./plex.nix)
  (
    final: prev:
    let
      packages = import ../packages { pkgs = final; };
    in
    {
      inherit (packages) ccusage;
      vimPlugins = prev.vimPlugins // {
        inherit (packages) ts-error-translator-nvim;
      };
    }
  )
  inputs.mcp-servers-nix.overlays.default
]

