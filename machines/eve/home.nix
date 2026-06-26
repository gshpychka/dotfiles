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
          # age identity for the sops CLI, fetched from 1Password at runtime
          sessionVariables.SOPS_AGE_KEY_CMD = "op read op://dev/sops-age-glib-op/credential";
        };
      };
  };
}
