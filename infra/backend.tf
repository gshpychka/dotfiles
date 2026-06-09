terraform {
  backend "gcs" {
    # Terraform backends cannot use variables, so the project id is hardcoded.
    # Must stay in sync with gcpProjectId in modules/common/values.nix.
    bucket = "status-glibsh-tf-state"
    prefix = "terraform/state"
  }
}
