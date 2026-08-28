{
  pkgs,
  ...
}:
{
  vimPlugins = pkgs.vimPlugins // {
    ts-error-translator-nvim = pkgs.callPackage ./ts-error-translator-nvim.nix { };
  };
  piPackages = pkgs.callPackage ./pi-packages { };
}
