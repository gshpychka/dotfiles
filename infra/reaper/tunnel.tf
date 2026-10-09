data "cloudflare_zone" "this" {
  zone_id = var.cloudflare_zone_id
}

# Ingress is configured on reaper by cloudflared (machines/reaper/spire). The
# tunnel secret is held only in reaper's sops credentials file, so
# tunnel_secret stays unset.
resource "cloudflare_zero_trust_tunnel_cloudflared" "reaper" {
  account_id = data.cloudflare_zone.this.account.id
  name       = "reaper-tunnel"
  config_src = "local"
}
