{
  config,
  pkgs,
  lib,
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
          ssh.enable = true;
          tmux.enable = true;
          tools.enable = true;
          zsh.enable = true;
        };

        home.packages = with pkgs; [ ];

        # age identity for the sops CLI, derived from the SSH host key at runtime.
        home.sessionVariables.SOPS_AGE_KEY_CMD = "sudo ${lib.getExe pkgs.ssh-to-age} -private-key -i /etc/ssh/ssh_host_ed25519_key";

        home.stateVersion = "24.05";
      };
  };
}
