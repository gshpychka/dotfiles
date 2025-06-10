{ lib, pkgs, config, ... }:
let enabled = builtins.elem "bash" config.my.neovim.languages;
in lib.mkIf enabled {
  my.neovim.languagePackages = lib.mkAfter [ pkgs.bash-language-server ];
  my.neovim.treeSitterLanguages = lib.mkAfter [ "bash" ];
}
