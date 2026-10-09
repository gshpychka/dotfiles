resource "cloudflare_dns_record" "spire" {
  zone_id = var.cloudflare_zone_id
  name    = "spire.${var.domain_name}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.reaper.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "SPIRE OIDC discovery provider via reaper-tunnel"
}
