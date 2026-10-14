include "root" {
  path = find_in_parent_folders("root.hcl")
}

# terraform/cloudflare of the oidc-issuer flake, at the revision flake.lock pins
terraform {
  source = "git::https://github.com/gshpychka/oidc-issuer.git//terraform/cloudflare?ref=${get_env("OIDC_ISSUER_REV")}"
}

locals {
  domain = get_env("TF_VAR_domain_name")
}

# state addresses from before this unit deployed the flake's module
generate "moved" {
  path      = "moved.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    moved {
      from = cloudflare_zero_trust_tunnel_cloudflared.reaper
      to   = cloudflare_zero_trust_tunnel_cloudflared.this
    }
    moved {
      from = cloudflare_dns_record.tokens
      to   = cloudflare_dns_record.issuer["tokens.${local.domain}"]
    }
    moved {
      from = cloudflare_dns_record.spire
      to   = cloudflare_dns_record.issuer["spire.${local.domain}"]
    }
  EOF
}

# cloudflare_api_token and cloudflare_zone_id come from secrets/infra/terraform.env
inputs = {
  # machines/reaper/cloudflare-tunnel.nix runs it
  tunnel_name = "reaper-tunnel"
  # services.oidc-issuer.{simple,spire}.host on reaper (machines/reaper/oidc-issuer.nix)
  hostnames = ["tokens.${local.domain}", "spire.${local.domain}"]
}
