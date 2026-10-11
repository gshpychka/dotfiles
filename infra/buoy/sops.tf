# Age key for SOPS encryption/decryption
# Stored in Secret Manager so it survives instance replacement

# the private key sits in plaintext in this unit's Terraform state
resource "age_secret_key" "sops" {}

resource "google_secret_manager_secret" "sops_age_key" {
  secret_id = "sops-age-key"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "sops_age_key" {
  secret      = google_secret_manager_secret.sops_age_key.id
  secret_data = age_secret_key.sops.secret_key
}

# Grant the VM's service account access to the secret
resource "google_secret_manager_secret_iam_member" "sops_age_key" {
  # the metadata server hands this account's token to any process on the VM
  count = var.grant_vm_sops_age_key_access ? 1 : 0

  secret_id = google_secret_manager_secret.sops_age_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}
