{
  pkgs,
  config,
  ...
}:
{
  home-manager = {
    users.${config.my.user} =
      { ... }:
      {
        imports = [
          ../../modules/home-manager
        ];

        my = {
          ai.enable = true;
          alacritty.enable = true;
          btop.enable = true;
          direnv.enable = true;
          finicky.enable = true;
          ghostty.enable = true;
          git.enable = true;
          gpg.enable = true;
          neovim.enable = true;
          nh.enable = true;
          npm.enable = true;
          ssh.enable = true;
          tmux.enable = true;
          tools.enable = true;
          zsh.enable = true;
        };

        home = {
          file.".hushlogin".text = "";
          stateVersion = "22.11";
          packages = with pkgs; [
            yubikey-manager
            sops
          ];
        };
      };
  };
}
