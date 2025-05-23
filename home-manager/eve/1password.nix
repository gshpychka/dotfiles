{ pkgs, ... }:
{
  programs = {
    ssh.matchBlocks._1p-auth = {
      host = "*";
      extraOptions.IdentityAgent = ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
    };
    git.signing.signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
  };

  xdg.configFile = {
    "1Password/ssh/agent.toml" = {
      source = (pkgs.formats.toml { }).generate "1password-ssh-agent-config" {
        "ssh-keys" = [
          { vault = "Personal"; }
          { vault = "Work"; }
        ];
      };
    };
  };
}
