# Manage the buoy-tunnel Cloudflare Tunnel declaratively (it was previously
# created out of band with `cloudflared tunnel create buoy-tunnel`).
# config_src = "local" keeps the ingress/routing config on the box, managed by
# cloudflared via machines/buoy/cloudflare-tunnel.nix - Terraform owns only the
# tunnel's existence and secret, not its routes.
#
# Adopting the already-running tunnel with no downtime:
#   - The import block below takes the live tunnel into state by its id, so it
#     is not recreated.
#   - cloudflare_tunnel_secret must be the tunnel's EXISTING secret (the
#     TunnelSecret in `sops -d secrets/buoy/cloudflare-tunnel.json`) so the
#     apply does not rotate it - buoy's credentials file stays valid.
# Verify `tf plan` shows no change that rotates tunnel_secret before applying.
# The import block can be removed after the first successful apply.
resource "cloudflare_zero_trust_tunnel_cloudflared" "buoy" {
  account_id    = var.cloudflare_account_id
  name          = "buoy-tunnel"
  config_src    = "local"
  tunnel_secret = var.cloudflare_tunnel_secret
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared.buoy
  id = "${var.cloudflare_account_id}/${var.cloudflare_tunnel_id}"
}
