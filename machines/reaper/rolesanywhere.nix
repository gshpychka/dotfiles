# AWS credentials for reaper's users through IAM Roles Anywhere
# (github:gshpychka/rolesanywhere). infra/aws trusts reaper's CA and holds the
# roles; its outputs are the ARNs for ~/.aws/config:
#   [profile reaper]
#   region = us-east-1
#   credential_process = rolesanywhere-credentials --trust-anchor-arn <trust_anchor_arn> --profile-arn <profile_arn> --role-arn <role ARN>
{ config, inputs, ... }:
{
  imports = [ inputs.rolesanywhere.nixosModules.default ];

  services.rolesanywhere = {
    enable = true;
    clients = [ config.my.user ];
    # Registering a new CA with AWS, whenever `journalctl -u rolesanywhere-ca`
    # says it was replaced:
    #   ssh reaper cat /var/lib/rolesanywhere/current/ca.pem > machines/reaper/rolesanywhere-ca.pem
    #   in the infra shell: cd infra/aws && tg apply
    #   deploy reaper
    caCertificate = ./rolesanywhere-ca.pem;
  };
}
