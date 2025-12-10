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

# GCS bucket for storing NixOS images
resource "google_storage_bucket" "nixos_images" {
  name          = "${var.gcp_project_id}-nixos-images"
  location      = var.gcp_region
  force_destroy = true

  uniform_bucket_level_access = true
}

locals {
  nixos_image_hash = filemd5(var.nixos_image_path)
}

# Upload NixOS image to GCS
resource "google_storage_bucket_object" "nixos_image" {
  name   = "nixos-${local.nixos_image_hash}.raw.tar.gz"
  bucket = google_storage_bucket.nixos_images.name
  source = var.nixos_image_path
}

# Create compute image from GCS object
resource "google_compute_image" "nixos" {
  name = "nixos-${local.nixos_image_hash}"

  raw_disk {
    source = "https://storage.googleapis.com/${google_storage_bucket.nixos_images.name}/${google_storage_bucket_object.nixos_image.name}"
  }

  guest_os_features {
    type = "VIRTIO_SCSI_MULTIQUEUE"
  }

  guest_os_features {
    type = "UEFI_COMPATIBLE"
  }

  guest_os_features {
    type = "GVNIC"
  }
}

resource "google_compute_instance" "vm" {
  name         = "vm"
  machine_type = "e2-micro"
  zone         = var.gcp_zone

  tags = ["vm"]

  boot_disk {
    initialize_params {
      image = google_compute_image.nixos.self_link
      size  = 20
      type  = "pd-standard"
    }
  }

  attached_disk {
    source      = google_compute_disk.data.self_link
    device_name = "data"
  }

  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.subnet.name

    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  # Allow Terraform to replace the instance when the image changes
  allow_stopping_for_update = true
}
