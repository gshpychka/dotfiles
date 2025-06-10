{ lib, pkgs, config, ... }:
let enabled = builtins.elem "yaml" config.my.neovim.languages;
in lib.mkIf enabled {
  my.neovim.languagePackages = lib.mkAfter [ pkgs.yaml-language-server ];
  my.neovim.treeSitterLanguages = lib.mkAfter [ "yaml" ];
}
