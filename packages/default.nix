{
  pkgs,
  ...
}:
{
  vimPlugins = pkgs.vimPlugins // {
    ts-error-translator-nvim = pkgs.callPackage ./ts-error-translator-nvim.nix { };
  };
  adguard-rules = pkgs.callPackage ./adguard-rules.nix { };
}
