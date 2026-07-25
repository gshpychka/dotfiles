variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "domain_name" {
  description = "Domain name managed by Cloudflare"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the buoy-tunnel"
  type        = string
  sensitive   = true
}

# Both of the below are only read by the import blocks in tunnel.tf / dns.tf, so
# they can be dropped from secrets/infra/terraform.env once those are removed
# after the first successful apply. cloudflared is not installed on eve, so look
# the ids up over the API (GET /accounts/{account_id}/cfd_tunnel?name=buoy-tunnel
# and GET /zones/{zone_id}/dns_records?type=CNAME&name=status.<domain>); the PR
# that introduced these has the exact commands.
variable "cloudflare_tunnel_id" {
  description = "UUID of the existing buoy-tunnel, used only to import it into Terraform state."
  type        = string
}

variable "status_dns_record_id" {
  description = "Cloudflare DNS record ID of the existing status.<domain> CNAME, used only to import it."
  type        = string
}

variable "data_disk_size" {
  description = "Size of the persistent data disk in GB"
  type        = number
  default     = 5
}

variable "nixos_image_path" {
  description = "Path to the NixOS GCE image tarball (.raw.tar.gz)"
  type        = string
  default     = "../result"
}
