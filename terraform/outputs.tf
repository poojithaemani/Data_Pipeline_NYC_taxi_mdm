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
  value = module.rds.db_endpoint
}

output "rds_address" {
  value = module.rds.db_address
}

output "rds_database" {
  value = module.rds.db_name
}

output "rds_security_group" {
  value = module.rds.db_security_group_id
}