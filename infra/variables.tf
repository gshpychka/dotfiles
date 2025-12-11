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

variable "hostname" {
  description = "Hostname for the VM (used for DNS A record)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for your domain"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions"
  type        = string
  sensitive   = true
}


variable "nixos_image_path" {
  description = "Path to the NixOS GCE image tarball (.raw.tar.gz)"
  type        = string
  default     = "result"
}

variable "data_disk_size" {
  description = "Size of the persistent data disk in GB"
  type        = number
  default     = 5
}
