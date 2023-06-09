{ config, pkgs, lib, inputs, system, ... }: {
  imports = [
    ./hammerspoon
    ./autoraise
    ./neovim
    ./tmux
    ./alacritty.nix
    ./git.nix
  ];

  programs = {
    ssh = {
      enable = true;
      matchBlocks = {
        "everything" = {
          host = "*";
          extraOptions = { IdentityAgent = ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"''; };
        };
      };
    };
  };
}
