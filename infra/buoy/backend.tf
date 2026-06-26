terraform {
  backend "gcs" {
    # Must stay in sync with gcpProjectId in modules/common/values.nix.
    bucket = "status-glibsh-tf-state"
    prefix = "terraform/state"
  }
}
