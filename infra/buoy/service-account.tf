# The VM's identity; its secret-access grant lives in sops.tf. Kept in the base
# root so the VM can be recreated without dropping the account.
resource "google_service_account" "vm" {
  account_id   = "nixos-vm"
  display_name = "VM Service Account"
}
