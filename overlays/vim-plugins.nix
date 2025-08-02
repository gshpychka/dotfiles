final: prev: {
  vimPlugins = prev.vimPlugins // {
    ts-error-translator-nvim = final.callPackage ../packages/ts-error-translator-nvim.nix { };
  };
}