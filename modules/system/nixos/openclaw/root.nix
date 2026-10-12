# Root on this host for the OpenClaw agent: sudo runs any command for the
# gateway user, authenticated by a key in the SSH agent of its environment.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  host = config.networking.hostName;
in
{
  options.my.openclaw.root.sshKey = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = ''
      Public key that authenticates the agent's sudo, which runs any command
      as root; the SSH agent at the gateway's SSH_AUTH_SOCK holds its private
      half. null gives the agent no sudo.
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.root.sshKey != null) {
    assertions = [
      {
        assertion = gw.environment ? SSH_AUTH_SOCK;
        message = "my.openclaw.root.sshKey authenticates with the SSH agent at services.openclaw-gateway.environment.SSH_AUTH_SOCK.";
      }
    ];

    security = {
      pam = {
        sshAgentAuth.enable = true;
        services.sudo.sshAgentAuth = true;
      };
      sudo.extraRules = [
        {
          users = [ gw.user ];
          commands = [ "ALL" ];
        }
      ];
    };
    # sudo's pam_ssh_agent_auth reads /etc/ssh/authorized_keys.d/%u, as does sshd
    users.users.${gw.user}.openssh.authorizedKeys.keys = [ cfg.root.sshKey ];

    my.openclaw.skills.nixos-rebuild = {
      description = "Rebuild and switch this host (${host}) from a checkout of its NixOS config.";
      text = ''
        Send a switch's output to a file:

            sudo nixos-rebuild switch --flake .#${host} >${cfg.workspace}/nixos-rebuild.log 2>&1

        A switch may restart this gateway mid-turn. The activation carries on
        in its own unit, writing to your command's output, and dies on a
        closed pipe. After the restart, the log shows how it ended.
      '';
    };
  };
}
