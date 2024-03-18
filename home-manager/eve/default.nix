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
    ./finicky
    ./neovim
    ./tmux
    ./alacritty.nix
    ./git.nix
    ./1password.nix
  ];

  home = {
    packages = with pkgs; [
      yubikey-manager
      zstd
      pam-reattach
      awscli2
      openscad
    ];
  };
  programs = {
    ssh = {
      enable = true;
      matchBlocks = {
        everything = {
          host = "*";
          setEnv = {
            TERM = "xterm-256color";
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
