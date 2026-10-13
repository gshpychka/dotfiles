variable "domain_name" {
  description = "Domain name managed by Cloudflare"
  type        = string
}

variable "user" {
  description = "Primary user (my.user), whose reaper tokens the test role trusts"
  type        = string
}

# Set by terragrunt.hcl from secrets/infra/aws.yaml.
variable "aws_account_id" {
  description = "The personal AWS account this unit manages"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}
