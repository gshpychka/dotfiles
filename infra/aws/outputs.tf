output "test_role_arn" {
  description = "For ~/.aws/config on reaper: credential_process = oidc-token aws --role-arn <this>"
  value       = aws_iam_role.reaper_user.arn
}
