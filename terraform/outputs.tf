output "glue_log_group" {
  value = module.cloudwatch.glue_log_group_name
}

output "lambda_log_group" {
  value = module.cloudwatch.lambda_log_group_name
}

output "api_gateway_log_group" {
  value = module.cloudwatch.api_gateway_log_group_name
}

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

# Phase 2 outputs - Glue Catalog & Crawlers & Athena
output "glue_bronze_db" {
  value = aws_glue_catalog_database.bronze.name
}

output "glue_silver_db" {
  value = aws_glue_catalog_database.silver.name
}

output "glue_gold_db" {
  value = aws_glue_catalog_database.gold.name
}

output "glue_master_db" {
  value = aws_glue_catalog_database.master.name
}

output "glue_role_arn" {
  value = aws_iam_role.glue_role.arn
}

output "bronze_crawler_name" {
  value = aws_glue_crawler.bronze.name
}

output "silver_crawler_name" {
  value = aws_glue_crawler.silver.name
}

output "gold_crawler_name" {
  value = aws_glue_crawler.gold.name
}

output "gold_summary_table_names" {
  description = "The names of the Gold summary tables created by the crawler."
  value = [
    # The crawler creates tables from the last component of the S3 path.
    for path in aws_glue_crawler.gold.delta_target[0].delta_tables : basename(path)
  ]
}

output "athena_workgroup" {
  value = aws_athena_workgroup.this.name
}

# Phase 2 outputs - Glue Jobs
output "silver_etl_job_name" {
  value = aws_glue_job.silver_etl.name
}

output "gold_etl_job_name" {
  value = aws_glue_job.gold_etl.name
}

output "golden_zone_etl_job_name" {
  value = aws_glue_job.golden_zone_etl.name
}