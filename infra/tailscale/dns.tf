resource "tailscale_dns_preferences" "this" {
  magic_dns = false
}

resource "tailscale_dns_search_paths" "this" {
  search_paths = [var.domain_name]
}
