output "instance_name" {
  description = "Name of the GCE instance"
  value       = google_compute_instance.vm.name
}

output "instance_external_ip" {
  description = "External IP address of the instance"
  value       = google_compute_address.static_ip.address
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh root@${var.hostname}.${var.domain_name}"
}

output "nixos_image_hash" {
  description = "Hash of the NixOS compute image"
  value       = local.nixos_image_hash
}

output "sops_age_public_key" {
  description = "Age public key for SOPS encryption (add to .sops.yaml)"
  value       = age_secret_key.sops.public_key
}
