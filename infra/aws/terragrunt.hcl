include "root" {
  path = find_in_parent_folders("root.hcl")
}

# terraform/aws of the oidc-issuer flake, at the revision flake.lock pins
terraform {
  source = "git::https://github.com/gshpychka/oidc-issuer.git//terraform/aws?ref=${get_env("OIDC_ISSUER_REV")}"
}

locals {
  user = get_env("TF_VAR_user")
  # no permissions: it proves the chain end to end (`aws sts get-caller-identity` needs none)
  test_role = "reaper-${local.user}-oidc-test"
}

# state addresses from before this unit deployed the flake's module
generate "moved" {
  path      = "moved.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    moved {
      from = aws_iam_openid_connect_provider.tokens
      to   = aws_iam_openid_connect_provider.issuer["simple"]
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
  issuers = {
    # services.oidc-issuer.simple on reaper (machines/reaper/oidc-issuer.nix)
    simple = {
      host = "tokens.${get_env("TF_VAR_domain_name")}"
      roles = {
        (local.test_role) = { subject = "reaper:${local.user}" }
      }
    }
  }
}
