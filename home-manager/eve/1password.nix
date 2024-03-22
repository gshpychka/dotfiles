{
  config,
  pkgs,
  lib,
  ...
}: {
  # TODO: only if ssh is enabled
  programs = {
    ssh.matchBlocks.everything.extraOptions.IdentityAgent = ''
      "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
    git.extraConfig.gpg.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
  };

  xdg.configFile = {
    "1Password/ssh/agent.toml" = {
      source = (pkgs.formats.toml {}).generate "1password-ssh-agent-config" {
        "ssh-keys" = [
          {vault = "Personal";}
          {vault = "Work";}
        ];
      };
    };
  };
}
