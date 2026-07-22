resource "cloudflare_dns_record" "vm" {
  zone_id = var.cloudflare_zone_id
  name    = "buoy.${var.domain_name}"
  content = google_compute_address.static_ip.address
  type    = "A"
  ttl     = 1
  proxied = false
  comment = "GCP VM static IP for SSH access"
}

# The Gatus status page (machines/buoy/gatus.nix) is served through the
# Cloudflare tunnel, so status.<domain> is a proxied CNAME to the tunnel. It
# was previously created with `cloudflared tunnel route dns buoy-tunnel
# status.<domain>`; the import block adopts that existing record unchanged.
# Remove the import block after the first successful apply.
resource "cloudflare_dns_record" "status" {
  zone_id = var.cloudflare_zone_id
  name    = "status.${var.domain_name}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.buoy.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "Gatus status page via buoy-tunnel"
}

import {
  to = cloudflare_dns_record.status
  id = "${var.cloudflare_zone_id}/${var.status_dns_record_id}"
}
