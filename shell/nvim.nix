{ config, pkgs, lib, ... }: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    extraPackages = [ pkgs.nodePackages_latest.pyright ];
    extraPython3Packages = pyPkgs: with pyPkgs; [ black ];
  };
}
