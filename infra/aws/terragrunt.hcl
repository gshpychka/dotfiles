include "root" {
  path = find_in_parent_folders("root.hcl")
}

# terraform/aws of the rolesanywhere flake, at the revision flake.lock pins
terraform {
  source = "git::https://github.com/gshpychka/rolesanywhere.git//terraform/aws?ref=${get_env("ROLESANYWHERE_REV")}"
}

locals {
  user = get_env("TF_VAR_user")
  # no permissions: it proves the chain end to end (`aws sts get-caller-identity` needs none)
  test_role = "reaper-${local.user}-rolesanywhere-test"
}

# state addresses from before this unit deployed the flake's module
generate "moved" {
  path      = "moved.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    moved {
      from = aws_rolesanywhere_trust_anchor.reaper
      to   = aws_rolesanywhere_trust_anchor.this
    }
    moved {
      from = aws_rolesanywhere_profile.reaper
      to   = aws_rolesanywhere_profile.this
    }
    moved {
      from = aws_iam_role.reaper_user
      to   = aws_iam_role.role["${local.test_role}"]
    }
  EOF
}

inputs = {
  # The one account this unit may touch, kept in sops rather than the repo.
  # secrets/infra/aws.yaml holds `account_id: "<12 digits>"`, quoted: an ID can
  # start with 0, which a YAML number would drop.
  aws_account_id = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/infra/aws.yaml")).account_id
  name           = "reaper"
  # services.rolesanywhere.caCertificate on reaper (machines/reaper/rolesanywhere.nix)
  ca_certificate = file("${get_repo_root()}/machines/reaper/rolesanywhere-ca.pem")
  roles = {
    (local.test_role) = { subject = "reaper:${local.user}" }
  }
}
