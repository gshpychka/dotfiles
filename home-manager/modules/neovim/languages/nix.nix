{ lib, pkgs, config, ... }:
let enabled = builtins.elem "nix" config.my.neovim.languages;
in lib.mkIf enabled {
  my.neovim.languagePackages = lib.mkAfter [ pkgs.nil ];
  my.neovim.treeSitterLanguages = lib.mkAfter [ "nix" ];
}
