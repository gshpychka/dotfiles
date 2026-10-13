# Root on this host for the OpenClaw agent: sudo for any command, authenticated
# by a key that an SSH agent holds for the gateway user.
{ config, lib, ... }:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  host = config.networking.hostName;
in
{
  options.my.openclaw.root = lib.mkOption {
    default = null;
    description = "The key the agent's sudo authenticates with; null leaves the agent without sudo.";
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          publicKey = lib.mkOption {
            type = lib.types.singleLineStr;
            description = "The key's public half.";
          };
          agentSocket = lib.mkOption {
            type = lib.types.str;
            description = "Socket of the SSH agent holding the key's private half.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg.enable && cfg.root != null) {
    services.openclaw-gateway.environment.SSH_AUTH_SOCK = cfg.root.agentSocket;

    security = {
      pam.sshAgentAuth.enable = true;
      sudo.extraRules = [
        {
          users = [ gw.user ];
          commands = [ "ALL" ];
        }
      ];
    };
    # the keys sudo's pam_ssh_agent_auth accepts for the gateway user
    users.users.${gw.user}.openssh.authorizedKeys.keys = [ cfg.root.publicKey ];

    my.openclaw.skills.nixos-rebuild = {
      description = "Rebuild and switch this host (${host}) from a checkout of its NixOS config.";
      text = ''
        In a checkout of this host's NixOS config, fast-forwarded to
        origin/main:

            sudo nixos-rebuild switch --flake .#${host}

        The switch installs the checkout as it is: an older one reverts this
        host, and nix sees only the files git tracks.

        A switch may restart this gateway mid-turn, ending the command; the
        activation runs on in its own unit. Its journal shows how the last
        one ended:

            sudo journalctl -u nixos-rebuild-switch-to-configuration -I
      '';
    };
  };
}
