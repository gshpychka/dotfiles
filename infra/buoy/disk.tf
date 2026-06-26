# Persistent data disk; survives instance replacement, so it stays in the base
# root rather than moving with the VM.
resource "google_compute_disk" "data" {
  name = "data"
  type = "pd-standard"
  zone = var.gcp_zone
  size = var.data_disk_size

  lifecycle {
    prevent_destroy = true
  }
}
