{
  pkgs,
  ...
}:
{
  ccusage = pkgs.callPackage ./ccusage.nix { };
  ts-error-translator-nvim = pkgs.callPackage ./ts-error-translator-nvim.nix { };
}