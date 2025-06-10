{ lib, pkgs, config, ... }:
let enabled = builtins.elem "python" config.my.neovim.languages;
in lib.mkIf enabled {
  my.neovim.languagePackages = lib.mkAfter [ pkgs.pyright ];
  my.neovim.treeSitterLanguages = lib.mkAfter [ "python" ];
}
