{
  config,
  pkgs,
  lib,
  ...
}: {
  xdg.configFile."hammerspoon.lua" = {source = ./init.lua;};
}
