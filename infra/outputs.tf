output "instance_external_ip" {
  description = "Reserved external IP the VM uses"
  value       = google_compute_address.static_ip.address
}

output "sops_age_public_key" {
  description = "Age public key for SOPS encryption (add to .sops.yaml)"
  value       = age_secret_key.sops.public_key
}
