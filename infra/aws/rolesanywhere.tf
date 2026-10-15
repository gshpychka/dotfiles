# AWS side of my.rolesAnywhere (modules/system/nixos/rolesanywhere.nix):
# trust reaper's CA, and a role its certificates can assume.
#
# reaper issues each local client a 5-minute certificate with the subject
# "reaper:<user>", signed by a CA key that never leaves its TPM2; Roles
# Anywhere trades it for credentials. Root on reaper can issue a certificate
# for any of reaper's subjects, and code running as a client user there can
# likely become root (sudo through the forwarded SSH agent, Nix
# trusted-users), so keep trusted roles to what a test can afford to lose.

locals {
  # reaper's hostname, which prefixes every subject ("<hostname>:<user>")
  issuer = "reaper"
}

# A new CA from reaper (rolesanywhere-ca replaces it when PCR 7 changes) is
# registered by copying its certificate into the repository and applying
# this, which updates the trust anchor in place; see
# machines/reaper/rolesanywhere.nix.
resource "aws_rolesanywhere_trust_anchor" "reaper" {
  name    = local.issuer
  enabled = true

  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data {
      x509_certificate_data = var.reaper_ca_certificate
    }
  }
}

# Only reaper's certificate for var.user, from reaper's trust anchor, can
# assume this role. It has no permissions: it proves the chain end to end
# (`aws sts get-caller-identity` needs none) and grants nothing. Real roles
# copy this trust policy with their own subject and permissions, and join the
# profile's role_arns.
data "aws_iam_policy_document" "reaper_user_trust" {
  statement {
    actions = [
      "sts:AssumeRole",
      # Roles Anywhere tags the session with the certificate's fields and sets
      # its source identity to the subject's CN
      "sts:TagSession",
      "sts:SetSourceIdentity",
    ]
    principals {
      type        = "Service"
      identifiers = ["rolesanywhere.amazonaws.com"]
    }
    # the certificate chains to reaper's CA, not another trust anchor's
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_rolesanywhere_trust_anchor.reaper.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/x509Subject/CN"
      values   = ["${local.issuer}:${var.user}"]
    }
  }
}

resource "aws_iam_role" "reaper_user" {
  name                 = "${local.issuer}-${var.user}-rolesanywhere-test"
  description          = "Assumable with reaper's Roles Anywhere certificate for ${local.issuer}:${var.user}"
  assume_role_policy   = data.aws_iam_policy_document.reaper_user_trust.json
  max_session_duration = 3600
}

# The roles reaper's certificates may ask for, and how long sessions last.
resource "aws_rolesanywhere_profile" "reaper" {
  name             = local.issuer
  enabled          = true
  role_arns        = [aws_iam_role.reaper_user.arn]
  duration_seconds = 3600
}
