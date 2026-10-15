include "root" {
  path = find_in_parent_folders("root.hcl")
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.0"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 6.0"
        }
      }
    }

    provider "aws" {
      # Roles Anywhere is regional: the trust anchor and profile live here, and
      # aws_signing_helper finds the region in the trust anchor's ARN
      region = "us-east-1"
      # refuses to plan or apply against any other account, such as a work one
      allowed_account_ids = [var.aws_account_id]
    }
  EOF
}

inputs = {
  # The one account this unit may touch, kept in sops rather than the repo.
  # secrets/infra/aws.yaml holds `account_id: "<12 digits>"`, quoted: an ID can
  # start with 0, which a YAML number would drop.
  aws_account_id = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/infra/aws.yaml")).account_id
  # reaper's my.rolesAnywhere.caCertificate (machines/reaper/rolesanywhere.nix),
  # which reaper generates on its first deploy and is copied here from it
  reaper_ca_certificate = file("${get_repo_root()}/machines/reaper/rolesanywhere-ca.pem")
}
