terraform {
  backend "gcs" {
    bucket = "status-glibsh-tf-state"
    prefix = "terraform/state"
  }
}
