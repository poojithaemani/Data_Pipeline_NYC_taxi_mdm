output "rds_endpoint" {
  value       = var.create_rds ? module.rds[0].db_endpoint : null
  description = "RDS endpoint (empty when create_rds = false)"
}

output "rds_address" {
  value       = var.create_rds ? module.rds[0].db_address : null
  description = "RDS address (empty when create_rds = false)"
}

output "rds_database" {
  value       = var.create_rds ? module.rds[0].db_name : null
  description = "RDS database name (empty when create_rds = false)"
}

output "rds_security_group" {
  value       = var.create_rds ? module.rds[0].db_security_group_id : null
  description = "RDS security group id (empty when create_rds = false)"
}

# Redshift Serverless outputs
output "redshift_namespace" {
  value       = var.create_redshift ? module.redshift[0].namespace_name : null
  description = "Redshift Serverless namespace (null when create_redshift = false)"
}

output "redshift_workgroup" {
  value       = var.create_redshift ? module.redshift[0].workgroup_name : null
  description = "Redshift Serverless workgroup (null when create_redshift = false)"
}

output "redshift_database" {
  value       = var.create_redshift ? module.redshift[0].database_name : null
  description = "Redshift Serverless database name"
}

output "redshift_endpoint" {
  value       = var.create_redshift ? module.redshift[0].endpoint_address : null
  description = "Redshift Serverless endpoint address"
}

output "redshift_port" {
  value       = var.create_redshift ? module.redshift[0].endpoint_port : null
  description = "Redshift Serverless endpoint port"
}

output "redshift_iam_role_arn" {
  value       = var.create_redshift ? module.redshift[0].iam_role_arn : null
  description = "ARN of the dedicated Redshift IAM role"
}

output "redshift_security_group" {
  value       = var.create_redshift ? module.redshift[0].security_group_id : null
  description = "Redshift Serverless security group id"
}

# Secrets - identifiers only, never the value.
output "redshift_admin_secret_arn" {
  value       = var.create_secrets ? module.secrets[0].redshift_admin_secret_arn : null
  description = "ARN of the Redshift admin secret used by the pipeline's Redshift Data API stage"
}

output "redshift_admin_secret_name" {
  value       = var.create_secrets ? module.secrets[0].redshift_admin_secret_name : null
  description = "Name of the Redshift admin secret"
}

# Security phase - identifiers only, never key material or credentials.
output "kms_key_arn" {
  value       = var.create_kms ? module.kms[0].key_arn : null
  description = "Customer managed key encrypting the data lake, Athena results and the secrets"
}

output "kms_alias" {
  value       = var.create_kms ? module.kms[0].alias_name : null
  description = "Alias of the customer managed key"
}

output "glue_vpc_connection_name" {
  value       = var.create_network ? module.network[0].glue_connection_name : null
  description = "Glue NETWORK connection placing database-facing jobs in the VPC"
}

output "glue_security_group_id" {
  value       = var.create_network ? module.network[0].glue_security_group_id : null
  description = "Security group for Glue ENIs; the only source allowed into RDS"
}

output "nat_gateway_public_ip" {
  value       = var.create_network ? module.network[0].nat_public_ip : null
  description = "Elastic IP of the NAT gateway used for Glue outbound traffic"
}

output "s3_vpc_endpoint_id" {
  value       = var.create_network ? module.network[0].s3_vpc_endpoint_id : null
  description = "S3 gateway endpoint keeping data-lake traffic off the NAT"
}

# CI/CD - identifiers only. Role ARNs are not credentials.
output "tfstate_bucket" {
  value       = aws_s3_bucket.tfstate.id
  description = "S3 bucket holding remote Terraform state"
}

output "github_oidc_provider_arn" {
  value       = var.create_cicd ? module.github_oidc[0].oidc_provider_arn : null
  description = "GitHub Actions OIDC identity provider"
}

output "github_actions_plan_role_arn" {
  value       = var.create_cicd ? module.github_oidc[0].plan_role_arn : null
  description = "Set as the AWS_ROLE_ARN repository variable for pull-request plans"
}

output "github_actions_apply_role_arn" {
  value       = var.create_cicd ? module.github_oidc[0].apply_role_arn : null
  description = "Set as AWS_ROLE_ARN on the protected production environment"
}
