# AWS side of the OIDC token issuer (modules/system/nixos/oidc-issuer.nix):
# trust its tokens, and a role they can assume.
#
# Applying this is what makes AWS accept the issuer's tokens; do it once a key
# is published at https://tokens.<domain>. Parked for the proof of concept
# (see the issuer's PR): root on any host can redirect tokens.<domain> with
# the shared Cloudflare credentials, and code running as a client user on
# reaper can likely become root (sudo via the forwarded SSH agent, Nix
# trusted user). Either way it can mint any reaper token this account
# accepts, so keep trusted roles to what a test can afford to lose.

locals {
  # my.oidcIssuer.host and my.oidcIssuer.audience in modules/common/oidc-issuer.nix
  issuer_host = "tokens.${var.domain_name}"
  audience    = "sts.amazonaws.com"
  # the signer's hostname, which prefixes every subject ("<hostname>:<user>")
  signer = "reaper"
}

resource "aws_iam_openid_connect_provider" "tokens" {
  url            = "https://${local.issuer_host}"
  client_id_list = [local.audience]
  # No thumbprint_list: the issuer host serves a publicly trusted (Cloudflare)
  # certificate, which AWS checks against its own CA list, ignoring thumbprints.
}

# Only reaper's token for var.user can assume this role. It has no
# permissions: it proves the chain end to end (`aws sts get-caller-identity`
# needs none) and grants nothing. Real roles copy this trust policy with
# their own subject and permissions.
data "aws_iam_policy_document" "reaper_user_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.tokens.arn]
    }
    # condition keys are the provider URL without https://, then the claim
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:aud"
      values   = [local.audience]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_host}:sub"
      values   = ["${local.signer}:${var.user}"]
    }
  }
}

resource "aws_iam_role" "reaper_user" {
  name                 = "${local.signer}-${var.user}-oidc-test"
  description          = "Assumable with ${local.signer}'s OIDC token for ${var.user}; no permissions"
  assume_role_policy   = data.aws_iam_policy_document.reaper_user_trust.json
  max_session_duration = 3600 # the minimum
}
