# IAM role and least-privilege policy for Glue (crawlers and jobs)

data "aws_caller_identity" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  glue_log_group_arn = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws-glue/jobs/${var.project_name}:*"
  s3_bucket_arn      = "arn:aws:s3:::${var.bucket_name}"
  s3_objects_arn_all = "arn:aws:s3:::${var.bucket_name}/*"
  s3_prefix_arns     = [for p in var.s3_data_prefixes : "arn:aws:s3:::${var.bucket_name}/${p}*"]
  glue_catalog_arn   = "arn:aws:glue:${var.aws_region}:${local.account_id}:catalog"
  glue_databases_arn = "arn:aws:glue:${var.aws_region}:${local.account_id}:database/*"
}

resource "aws_iam_role" "glue_role" {
  name = var.glue_role_name != "" ? var.glue_role_name : "${var.project_name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "glue.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Least-privilege policy for Glue services (crawlers & jobs)
data "aws_iam_policy_document" "glue_policy" {
  statement {
    sid    = "S3BucketList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [local.s3_bucket_arn]
  }

  statement {
    sid    = "S3ObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = concat(local.s3_prefix_arns, [local.s3_objects_arn_all])
  }

  statement {
    sid    = "GlueCatalogAccess"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:BatchCreatePartition",
      "glue:GetPartitions"
    ]
    resources = [local.glue_catalog_arn, local.glue_databases_arn]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [local.glue_log_group_arn]
  }
}

resource "aws_iam_role_policy" "glue_policy" {
  name   = "${aws_iam_role.glue_role.name}-policy"
  role   = aws_iam_role.glue_role.id
  policy = data.aws_iam_policy_document.glue_policy.json
}

