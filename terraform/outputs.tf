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
  value       = module.rds.db_endpoint
  description = "RDS endpoint (empty when create_rds = false)"
}

output "rds_address" {
  value       = module.rds.db_address
  description = "RDS address (empty when create_rds = false)"
}

output "rds_database" {
  value       = module.rds.db_name
  description = "RDS database name (empty when create_rds = false)"
}

output "rds_security_group" {
  value       = module.rds.db_security_group_id
  description = "RDS security group id (empty when create_rds = false)"
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