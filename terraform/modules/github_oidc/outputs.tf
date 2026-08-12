# Role ARNs are identifiers, not credentials - they are safe to publish and
# are exactly what the GitHub repository variables AWS_ROLE_ARN must hold.

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "plan_role_arn" {
  description = "Read-only role assumed by pull-request Terraform plans. Set as the AWS_ROLE_ARN repository variable."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Write role assumed only from the protected environment. Set as AWS_ROLE_ARN on that environment."
  value       = aws_iam_role.apply.arn
}
