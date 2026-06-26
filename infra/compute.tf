# VM identity and persistent storage. These stay in the base root so
# the VM can be recreated without recreating its service account or data disk.

# Dedicated service account for the VM
resource "google_service_account" "vm" {
  account_id   = "nixos-vm"
  display_name = "VM Service Account"
}

# Persistent data disk (survives instance replacement)
resource "google_compute_disk" "data" {
  name = "data"
  type = "pd-standard"
  zone = var.gcp_zone
  size = var.data_disk_size

  lifecycle {
    prevent_destroy = false
  }
}
