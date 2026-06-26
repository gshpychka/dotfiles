terraform {
  backend "gcs" {
    # Must stay in sync with $TF_STATE_BUCKET
    bucket = "status-glibsh-tf-state"
    prefix = "terraform/state"
  }
}
