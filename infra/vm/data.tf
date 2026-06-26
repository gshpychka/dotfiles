# Network, static IP, service account, and data disk are created by the base
# root (../). The VM looks them up by name from live GCP rather than coupling to
# base's remote state, so it can be planned and applied without base being
# applied first. Names match the resources defined in ../network.tf and
# ../compute.tf.
data "google_compute_network" "vpc" {
  name = "vpc"
}

data "google_compute_subnetwork" "subnet" {
  name   = "subnet"
  region = var.gcp_region
}

data "google_compute_address" "static_ip" {
  name   = "static-ip"
  region = var.gcp_region
}

data "google_service_account" "vm" {
  account_id = "nixos-vm"
}

data "google_compute_disk" "data" {
  name = "data"
  zone = var.gcp_zone
}
