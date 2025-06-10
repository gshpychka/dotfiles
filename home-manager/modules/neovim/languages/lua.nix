{ lib, pkgs, config, ... }:
let enabled = builtins.elem "lua" config.my.neovim.languages;
in lib.mkIf enabled {
  my.neovim.languagePackages = lib.mkAfter [ pkgs.lua-language-server ];
  my.neovim.treeSitterLanguages = lib.mkAfter [ "lua" ];
}
