{ lib, pkgs, config, ... }:
let enabled = builtins.elem "json" config.my.neovim.languages;
in lib.mkIf enabled {
  my.neovim.languagePackages = lib.mkAfter [ pkgs.vscode-langservers-extracted ];
  my.neovim.treeSitterLanguages = lib.mkAfter [ "json" ];
}
