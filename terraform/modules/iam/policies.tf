############################################
# Glue S3 Policy
############################################

data "aws_iam_policy_document" "glue_s3_policy" {

  statement {
    sid    = "S3Access"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      "arn:aws:s3:::${var.bucket_name}"
    ]
  }

  statement {
    sid    = "S3ObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "arn:aws:s3:::${var.bucket_name}/*"
    ]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }

}

############################################
# Lambda S3 Policy
############################################

data "aws_iam_policy_document" "lambda_s3_policy" {

  statement {
    sid    = "S3Access"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${var.bucket_name}",
      "arn:aws:s3:::${var.bucket_name}/*"
    ]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }

}

############################################
# EventBridge Policy
############################################

data "aws_iam_policy_document" "eventbridge_policy" {

  statement {
    sid    = "GlueJobs"
    effect = "Allow"

    actions = [
      "glue:StartJobRun"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "InvokeLambda"
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction"
    ]

    resources = ["*"]
  }

}