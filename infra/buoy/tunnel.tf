# Manage the buoy-tunnel Cloudflare Tunnel declaratively (it was previously
# created out of band with `cloudflared tunnel create buoy-tunnel`).
# config_src = "local" keeps the ingress/routing config on the box, managed by
# cloudflared via machines/buoy/cloudflare-tunnel.nix.
#
# Terraform adopts the existing tunnel by id (import block) but deliberately
# does NOT manage tunnel_secret: that secret is a cloudflared run credential
# that already lives in secrets/buoy/cloudflare-tunnel.json, and Terraform
# needs neither it to own the tunnel's identity nor to build the cfargotunnel
# CNAMEs. Leaving it unset keeps the secret in exactly one place and means
# `tf apply` can never rotate it (no downtime). The import block can be removed
# after the first successful apply.
resource "cloudflare_zero_trust_tunnel_cloudflared" "buoy" {
  account_id = var.cloudflare_account_id
  name       = "buoy-tunnel"
  config_src = "local"
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared.buoy
  id = "${var.cloudflare_account_id}/${var.cloudflare_tunnel_id}"
}
