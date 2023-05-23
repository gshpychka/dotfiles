{ config, pkgs, lib, ... }: {
  xdg.configFile."Autoraise/config" = {
    source = ./config;
  };
}
