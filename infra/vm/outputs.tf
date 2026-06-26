output "instance_name" {
  description = "Name of the GCE instance"
  value       = google_compute_instance.vm.name
}

output "nixos_image_hash" {
  description = "Hash of the NixOS compute image"
  value       = local.nixos_image_hash
}
