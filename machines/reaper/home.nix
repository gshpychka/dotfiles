{
  config,
  pkgs,
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
          btop.enable = true;
          direnv.enable = true;
          git.enable = true;
          gpg.enable = true;
          neovim.enable = true;
          nh.enable = true;
          pi = {
            enable = true;
            pituitary.enable = true;
          };
          sops = {
            enable = true;
            ageIdentity = "host-key";
          };
          ssh.enable = true;
          tmux.enable = true;
          tools.enable = true;
          zsh.enable = true;
        };

        home.packages = with pkgs; [ ];

        home.stateVersion = "24.05";
      };
  };
}
