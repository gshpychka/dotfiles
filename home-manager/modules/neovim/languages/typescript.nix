{ lib, pkgs, config, ... }:
let enabled = builtins.elem "typescript" config.my.neovim.languages;
in lib.mkIf enabled {
  my.neovim.languagePackages = lib.mkAfter [ pkgs.nodePackages_latest.typescript-language-server pkgs.vscode-langservers-extracted ];
  my.neovim.treeSitterLanguages = lib.mkAfter [ "typescript" "javascript" ];
  my.neovim.extraPlugins = lib.mkAfter (with pkgs.vimPlugins; [ typescript-tools-nvim tsc-nvim ]);
}
