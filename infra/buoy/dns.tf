resource "cloudflare_dns_record" "vm" {
  zone_id = var.cloudflare_zone_id
  name    = "buoy.${var.domain_name}"
  content = google_compute_address.static_ip.address
  type    = "A"
  ttl     = 1
  proxied = false
  comment = "GCP VM static IP for SSH access"
}
