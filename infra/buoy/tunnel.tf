data "cloudflare_zone" "this" {
  zone_id = var.cloudflare_zone_id
}

# Ingress is configured on buoy by cloudflared. The tunnel secret is held only
# in buoy's sops credentials file, so tunnel_secret stays unset.
resource "cloudflare_zero_trust_tunnel_cloudflared" "buoy" {
  account_id = data.cloudflare_zone.this.account.id
  name       = "buoy-tunnel"
  config_src = "local"
}
