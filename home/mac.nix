{ config, pkgs, lib, ... }: {
  programs = {
    zsh = {
      initExtraBeforeCompInit = ''
        eval "$(/opt/homebrew/bin/brew shellenv)"
        eval "$(starship init zsh)"
      '';

      sessionVariables = {
      };
    };
  };
}
