resource "cloudflare_dns_record" "vm" {
  zone_id = var.cloudflare_zone_id
  name    = "buoy.${var.domain_name}"
  content = google_compute_address.static_ip.address
  type    = "A"
  ttl     = 1
  proxied = false
  comment = "GCP VM static IP for SSH access"
}

resource "cloudflare_dns_record" "status" {
  zone_id = var.cloudflare_zone_id
  name    = "status.${var.domain_name}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.buoy.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "Gatus status page via buoy-tunnel"
}

resource "cloudflare_dns_record" "ntfy" {
  zone_id = var.cloudflare_zone_id
  name    = "ntfy.${var.domain_name}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.buoy.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "ntfy via buoy-tunnel"
}
