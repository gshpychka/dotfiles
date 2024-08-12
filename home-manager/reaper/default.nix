{
  config,
  pkgs,
  lib,
  inputs,
  system,
  ...
}: {
  imports = [
    ../common
    ../common/tmux
    ../common/neovim
  ];
}
