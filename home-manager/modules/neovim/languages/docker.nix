{ lib, pkgs, config, ... }:
let enabled = builtins.elem "docker" config.my.neovim.languages;
in lib.mkIf enabled {
  my.neovim.languagePackages = lib.mkAfter [ pkgs.nodePackages_latest.dockerfile-language-server-nodejs ];
  my.neovim.treeSitterLanguages = lib.mkAfter [ "dockerfile" ];
}
