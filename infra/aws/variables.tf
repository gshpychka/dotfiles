variable "user" {
  description = "Primary user (my.user), whose reaper certificates the test role trusts"
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

# Set by terragrunt.hcl from machines/reaper/rolesanywhere-ca.pem.
variable "reaper_ca_certificate" {
  description = "reaper's CA certificate (PEM), whose key is in reaper's TPM2"
  type        = string

  validation {
    condition     = can(regex("^-----BEGIN CERTIFICATE-----", var.reaper_ca_certificate))
    error_message = "reaper_ca_certificate must be a PEM certificate."
  }
}
