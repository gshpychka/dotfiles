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
      # IAM is global; the provider still needs a region
      region = "us-east-1"
      # refuses to plan or apply against any other account, such as a work one
      allowed_account_ids = [var.aws_account_id]
    }
  EOF
}

# The one account this unit may touch, kept in sops rather than the repo.
# secrets/infra/aws.yaml holds `account_id: "<12 digits>"`, quoted: an ID can
# start with 0, which a YAML number would drop.
inputs = {
  aws_account_id = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/infra/aws.yaml")).account_id
}
