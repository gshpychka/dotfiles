{
  pkgs,
  ...
}:
{
  ccusage = pkgs.callPackage ./ccusage.nix { };
  vimPlugins = pkgs.vimPlugins // {
    ts-error-translator-nvim = pkgs.callPackage ./ts-error-translator-nvim.nix { };
  };
}

