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
# Was missing while the other three Glue jobs were exported. Added with the
# orchestration batch so every deployed job has an output.
output "warehouse_export_etl_job_name" {
  value = aws_glue_job.warehouse_export_etl.name
}

# Orchestration and observability
output "pipeline_state_machine_arn" {
  value       = var.create_orchestration ? module.stepfunctions[0].state_machine_arn : null
  description = "ARN of the end-to-end pipeline state machine"
}

output "pipeline_state_machine_name" {
  value       = var.create_orchestration ? module.stepfunctions[0].state_machine_name : null
  description = "Name of the end-to-end pipeline state machine"
}

output "pipeline_state_machine_log_group" {
  value       = var.create_orchestration ? module.stepfunctions[0].log_group_name : null
  description = "Log group receiving state machine execution history"
}

output "pipeline_copy_statement_count" {
  value       = var.create_orchestration ? module.stepfunctions[0].copy_statement_count : null
  description = "Statements parsed from services/redshift/load/02_copy_from_s3.sql into the Redshift COPY stage"
}

output "alerts_topic_arn" {
  value       = var.create_orchestration ? module.monitoring[0].alerts_topic_arn : null
  description = "SNS topic for pipeline alarms and failure notifications"
}

output "monitoring_dashboard_name" {
  value       = var.create_orchestration ? module.monitoring[0].dashboard_name : null
  description = "CloudWatch dashboard for the pipeline"
}

output "monitoring_alarm_names" {
  value       = var.create_orchestration ? module.monitoring[0].alarm_names : null
  description = "CloudWatch alarms guarding the pipeline"
}

# Secrets - identifiers only, never the value.
output "redshift_admin_secret_arn" {
  value       = var.create_orchestration ? module.secrets[0].redshift_admin_secret_arn : null
  description = "ARN of the Redshift admin secret used by the pipeline's Redshift Data API stage"
}

output "redshift_admin_secret_name" {
  value       = var.create_orchestration ? module.secrets[0].redshift_admin_secret_name : null
  description = "Name of the Redshift admin secret"
}
