# Age key for SOPS encryption/decryption
# Stored in Secret Manager so it survives instance replacement
#
# age_secret_key keeps the private key in plaintext in this unit's Terraform
# state, so read access to the state bucket (TF_STATE_BUCKET) is enough to
# decrypt everything buoy can: secrets/buoy/* and secrets/common/*. Guard the
# bucket's IAM like the key itself.

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

# Lets the VM's service account read the age key. Only the bootstrap image reads
# it (fetch-sops-age-key in infra/nixos/configuration.nix), and only a fresh
# data disk needs that: the disk outlives instance replacement, and the
# bootstrap fetch keeps the key already on it when it can't read the secret.
#
# Off by default: any process that can reach the metadata server gets a token
# for this account, so a standing grant would hand the key to whatever gets
# that far. machines/buoy/metadata-server.nix also limits the metadata server
# to root on buoy; this keeps the key safe if that rule isn't loaded.
#
# Turn it on when the bootstrap image has to fetch the key: a fresh data disk
# (new project, lost disk) or a rotated key. In infra/buoy:
#   tg apply -var grant_vm_sops_age_key_access=true
#     rotating: also -replace=age_secret_key.sops -replace=google_compute_instance.vm
#     (only the bootstrap image has fetch-sops-age-key, and only a new VM boots it)
#   if the bootstrap image booted before the grant took effect (IAM can take a
#   minute or two), on buoy: systemctl restart fetch-sops-age-key
#   deploy buoy (runbook in machines/buoy/default.nix; rekey if buoy_host changed)
#   tg apply   # revokes the grant
resource "google_secret_manager_secret_iam_member" "sops_age_key" {
  count = var.grant_vm_sops_age_key_access ? 1 : 0

  secret_id = google_secret_manager_secret.sops_age_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}
