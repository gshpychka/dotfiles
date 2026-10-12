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
  };
}
