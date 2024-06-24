{
  config,
  pkgs,
  lib,
  inputs,
  system,
  ...
}: {
  imports = [];

  programs = {
    git = {
      enable = true;
      userEmail = "23005347+gshpychka@users.noreply.github.com";
      userName = "Glib Shpychka";
    };
  };
}
