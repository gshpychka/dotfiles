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

variable "cloudflare_tunnel_id" {
  description = "UUID of the existing buoy-tunnel (`cloudflared tunnel list`), used only to import it into Terraform state."
  type        = string
}

variable "cloudflare_tunnel_secret" {
  description = "Existing buoy-tunnel secret - the TunnelSecret in `sops -d secrets/buoy/cloudflare-tunnel.json` (base64). Set to the current value so `tf apply` does not rotate it (no downtime)."
  type        = string
  sensitive   = true
}

variable "status_dns_record_id" {
  description = "Cloudflare DNS record ID of the existing status.<domain> CNAME, used only to import it (GET /zones/{zone_id}/dns_records?name=status.<domain>)."
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
