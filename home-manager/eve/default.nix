{ config, pkgs, lib, inputs, system, ... }: {
  imports = [
    ./hammerspoon
  ];

  programs = {
    ssh = {
      enable = true;
      extraConfig = ''
        Host *
          IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
      '';
    };
  };
}