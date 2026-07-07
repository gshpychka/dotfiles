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
        tailscale = {
          source  = "tailscale/tailscale"
          version = "~> 0.29"
        }
      }
    }

    provider "tailscale" {
      oauth_client_id     = var.tailscale_oauth_client_id
      oauth_client_secret = var.tailscale_oauth_client_secret
    }
  EOF
}
