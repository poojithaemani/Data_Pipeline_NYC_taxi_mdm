# Identifiers only. The secret VALUES are never exposed through an output -
# doing so would put a password into `terraform output` and into any CI log
# that renders outputs.

output "redshift_admin_secret_arn" {
  description = "ARN of the Redshift admin secret. An ARN is an identifier, not a credential."
  value       = aws_secretsmanager_secret.redshift_admin.arn
}

output "redshift_admin_secret_name" {
  description = "Name of the Redshift admin secret"
  value       = aws_secretsmanager_secret.redshift_admin.name
}
