{
  pkgs,
  ...
}:
{
  ts-error-translator-nvim = pkgs.callPackage ./ts-error-translator-nvim.nix { };
}