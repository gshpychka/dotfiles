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

variable "nixos_image_path" {
  description = "Path to the NixOS GCE image tarball (.raw.tar.gz)"
  type        = string
  # built in the parent dir: `nix build ..#gce-image -o result`
  default = "../result"
}
