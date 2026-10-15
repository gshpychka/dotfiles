# For ~/.aws/config on reaper (machines/reaper/rolesanywhere.nix):
#   credential_process = rolesanywhere-credentials --trust-anchor-arn <trust_anchor_arn> --profile-arn <profile_arn> --role-arn <test_role_arn>

output "trust_anchor_arn" {
  description = "reaper's Roles Anywhere trust anchor"
  value       = aws_rolesanywhere_trust_anchor.reaper.arn
}

output "profile_arn" {
  description = "reaper's Roles Anywhere profile"
  value       = aws_rolesanywhere_profile.reaper.arn
}

output "test_role_arn" {
  description = "The permissionless role reaper's certificate for my.user assumes"
  value       = aws_iam_role.reaper_user.arn
}
