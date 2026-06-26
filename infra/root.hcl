# Shared GCS backend for all infra units; providers are generated per unit.

terraform_binary = "terraform"

remote_state {
  backend = "gcs"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket = get_env("TF_STATE_BUCKET")
    prefix = "terraform/${path_relative_to_include()}"
  }
}
