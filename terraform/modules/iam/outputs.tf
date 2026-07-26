output "glue_role_name" {
  description = "Glue IAM Role Name"
  value       = aws_iam_role.glue_role.name
}

output "glue_role_arn" {
  description = "Glue IAM Role ARN"
  value       = aws_iam_role.glue_role.arn
}

output "lambda_role_name" {
  description = "Lambda IAM Role Name"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "Lambda IAM Role ARN"
  value       = aws_iam_role.lambda_role.arn
}

output "eventbridge_role_name" {
  description = "EventBridge IAM Role Name"
  value       = aws_iam_role.eventbridge_role.name
}

output "eventbridge_role_arn" {
  description = "EventBridge IAM Role ARN"
  value       = aws_iam_role.eventbridge_role.arn
}

output "glue_s3_policy_arn" {
  description = "Glue S3 Policy ARN"
  value       = aws_iam_policy.glue_s3_policy.arn
}

output "lambda_s3_policy_arn" {
  description = "Lambda S3 Policy ARN"
  value       = aws_iam_policy.lambda_s3_policy.arn
}

output "eventbridge_policy_arn" {
  description = "EventBridge Policy ARN"
  value       = aws_iam_policy.eventbridge_policy.arn
}