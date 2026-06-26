include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  # Absolute path — terragrunt runs terraform from .terragrunt-cache, not this dir.
  nixos_image_path = "${get_repo_root()}/infra/result"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.0"
      required_providers {
        google = {
          source  = "hashicorp/google"
          version = "~> 7.0"
        }
        cloudflare = {
          source  = "cloudflare/cloudflare"
          version = "~> 5.0"
        }
        age = {
          source  = "clementblaise/age"
          version = "~> 0.1"
        }
      }
    }

    provider "google" {
      project = var.gcp_project_id
      region  = var.gcp_region
      zone    = var.gcp_zone
    }

    provider "cloudflare" {
      api_token = var.cloudflare_api_token
    }
  EOF
}
