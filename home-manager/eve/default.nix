{
  config,
  pkgs,
  lib,
  inputs,
  system,
  ...
}: {
  imports = [
    # ./linkapps.nix
    # ./hammerspoon
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
          extraOptions = {
            IdentityAgent = ''
              "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
          };
        };
        ${config.shared.harborHost} = {
          host = "${config.shared.harborHost}.${config.shared.localDomain}";
          user = config.shared.harborUsername;
          port = config.shared.harborSshPort;
          extraOptions = {ForwardAgent = "yes";};
        };
      };
    };
    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
      enableBashIntegration = false;
      enableNushellIntegration = false;
    };
  };
}
