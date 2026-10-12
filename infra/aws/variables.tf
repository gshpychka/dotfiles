variable "domain_name" {
  description = "Domain name managed by Cloudflare"
  type        = string
}

variable "user" {
  description = "Primary user (my.user), whose reaper tokens the test role trusts"
  type        = string
}

# Deliberately not in the repo: add it to secrets/infra/terraform.env with
# `sops secrets/infra/terraform.env`. Until then Terraform stops before
# planning, so nothing runs against an account nobody chose.
variable "aws_account_id" {
  description = "The personal AWS account this unit manages (TF_VAR_aws_account_id in secrets/infra/terraform.env)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}
