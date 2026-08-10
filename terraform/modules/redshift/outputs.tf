output "namespace_name" {
  description = "Redshift Serverless namespace name"
  value       = aws_redshiftserverless_namespace.this.namespace_name
}

output "namespace_arn" {
  description = "Redshift Serverless namespace ARN"
  value       = aws_redshiftserverless_namespace.this.arn
}

output "database_name" {
  description = "Initial database created in the namespace"
  value       = aws_redshiftserverless_namespace.this.db_name
}

output "workgroup_name" {
  description = "Redshift Serverless workgroup name"
  value       = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "workgroup_id" {
  description = "Redshift Serverless workgroup ID"
  value       = aws_redshiftserverless_workgroup.this.workgroup_id
}

output "endpoint_address" {
  description = "Redshift Serverless endpoint address"
  value       = aws_redshiftserverless_workgroup.this.endpoint[0].address
}

output "endpoint_port" {
  description = "Redshift Serverless endpoint port"
  value       = aws_redshiftserverless_workgroup.this.endpoint[0].port
}

output "iam_role_arn" {
  description = "ARN of the dedicated Redshift IAM role"
  value       = aws_iam_role.redshift.arn
}

output "security_group_id" {
  description = "Security group ID for the Redshift Serverless workgroup"
  value       = aws_security_group.redshift.id
}

output "base_capacity" {
  description = "Configured base capacity in RPUs"
  value       = aws_redshiftserverless_workgroup.this.base_capacity
}
