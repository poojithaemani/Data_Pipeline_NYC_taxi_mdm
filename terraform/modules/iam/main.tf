############################################
# IAM Assume Role Policies
############################################

data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "eventbridge_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

############################################
# Glue Execution Role
############################################

resource "aws_iam_role" "glue_role" {
  name               = "${var.project_name}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

############################################
# Lambda Execution Role
############################################

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

############################################
# EventBridge Execution Role
############################################

resource "aws_iam_role" "eventbridge_role" {
  name               = "${var.project_name}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume_role.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

############################################
# AWS Managed Policies
############################################

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

############################################
# Custom Policies
############################################

resource "aws_iam_policy" "glue_s3_policy" {
  name   = "${var.project_name}-glue-s3-policy"
  policy = data.aws_iam_policy_document.glue_s3_policy.json
}

resource "aws_iam_policy" "lambda_s3_policy" {
  name   = "${var.project_name}-lambda-s3-policy"
  policy = data.aws_iam_policy_document.lambda_s3_policy.json
}

resource "aws_iam_policy" "eventbridge_policy" {
  name   = "${var.project_name}-eventbridge-policy"
  policy = data.aws_iam_policy_document.eventbridge_policy.json
}

############################################
# Attach Custom Policies
############################################

resource "aws_iam_role_policy_attachment" "attach_glue_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_lambda_s3" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_eventbridge_policy" {
  role       = aws_iam_role.eventbridge_role.name
  policy_arn = aws_iam_policy.eventbridge_policy.arn
}