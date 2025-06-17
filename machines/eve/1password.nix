{
  pkgs,
  config,
  lib,
  ...
}:
{
  environment = {
    systemPackages = with pkgs; [
      # CLI has to be installed system-wide
      _1password-cli
    ];
  };
  homebrew = {
    casks = [ "1password" ];
    masApps = {
      "1Password for Safari" = 1569813296;
    };
  };
  home-manager.users.${config.system.primaryUser} = (
    let
      hmConfig = config.home-manager.users.${config.system.primaryUser};
    in
    {
      programs = {
        ssh.matchBlocks._1p-auth = lib.mkIf hmConfig.programs.ssh.enable {
          host = "*";
          extraOptions.IdentityAgent = ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
        };
        git.signing.signer = lib.mkIf (
          hmConfig.programs.git.enable && hmConfig.programs.git.signing.format == "ssh"
        ) "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      };

      xdg.configFile = {
        "1Password/ssh/agent.toml" = lib.mkIf hmConfig.programs.ssh.enable {
          source = (pkgs.formats.toml { }).generate "1password-ssh-agent-config" {
            "ssh-keys" = [
              { vault = "Personal"; }
              { vault = "Work"; }
            ];
          };
        };
      };
    }
  );
}
