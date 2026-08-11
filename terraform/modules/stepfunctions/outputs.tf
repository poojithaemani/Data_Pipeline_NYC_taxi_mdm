output "state_machine_arn" {
  description = "ARN of the pipeline state machine"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "state_machine_name" {
  description = "Name of the pipeline state machine"
  value       = aws_sfn_state_machine.pipeline.name
}

output "role_arn" {
  description = "ARN of the state machine execution role"
  value       = aws_iam_role.sfn.arn
}

output "log_group_name" {
  description = "CloudWatch log group receiving state machine execution logs"
  value       = aws_cloudwatch_log_group.sfn.name
}

output "copy_statement_count" {
  description = "Number of SQL statements parsed out of 02_copy_from_s3.sql and handed to the Redshift Data API"
  value       = length(local.copy_statements)
}
