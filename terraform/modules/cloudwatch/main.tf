############################################
# Glue Log Group
############################################

resource "aws_cloudwatch_log_group" "glue" {

  name              = "/aws-glue/jobs/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

}

############################################
# Lambda Log Group
############################################

resource "aws_cloudwatch_log_group" "lambda" {

  name              = "/aws/lambda/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

}

############################################
# API Gateway Log Group
############################################

resource "aws_cloudwatch_log_group" "apigateway" {

  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

}