output "glue_log_group_name" {
  value = aws_cloudwatch_log_group.glue.name
}

output "lambda_log_group_name" {
  value = aws_cloudwatch_log_group.lambda.name
}

output "api_gateway_log_group_name" {
  value = aws_cloudwatch_log_group.apigateway.name
}

output "glue_log_group_arn" {
  value = aws_cloudwatch_log_group.glue.arn
}

output "lambda_log_group_arn" {
  value = aws_cloudwatch_log_group.lambda.arn
}

output "api_gateway_log_group_arn" {
  value = aws_cloudwatch_log_group.apigateway.arn
}