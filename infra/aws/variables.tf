variable "domain_name" {
  description = "Domain name managed by Cloudflare"
  type        = string
}

variable "user" {
  description = "Primary user (my.user), whose reaper tokens the test role trusts"
  type        = string
}

variable "aws_account_id" {
  description = "The personal AWS account this unit manages (TF_VAR_aws_account_id in secrets/infra/terraform.env)"
  type        = string
}
