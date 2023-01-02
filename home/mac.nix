{ config, pkgs, lib, ... }: {
  programs = {
    zsh = {
      initExtraBeforeCompInit = ''
        eval "$(/usr/local/bin/brew shellenv)"
        eval "$(starship init zsh)"
      '';

      sessionVariables = {
      };
    };
  };
}
