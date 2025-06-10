{ lib, pkgs, config, ... }:
let enabled = builtins.elem "zig" config.my.neovim.languages;
in lib.mkIf enabled {
  my.neovim.languagePackages = lib.mkAfter [ pkgs.zls ];
  my.neovim.treeSitterLanguages = lib.mkAfter [ "zig" ];
}
