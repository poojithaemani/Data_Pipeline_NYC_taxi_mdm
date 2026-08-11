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

  # Security phase: the database password is no longer passed as a job
  # argument. The two database-facing jobs read this one secret at runtime.
  dynamic "statement" {
    for_each = var.create_orchestration ? [1] : []
    content {
      sid       = "ReadRdsSecret"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [module.secrets[0].rds_master_secret_arn]
    }
  }

  # Needed both to decrypt that secret and to read and write S3 objects now
  # that the bucket's default encryption is the CMK. Encrypt and
  # GenerateDataKey cover writes; Decrypt covers reads.
  dynamic "statement" {
    for_each = var.create_orchestration ? [1] : []
    content {
      sid    = "UseProjectKey"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = [module.kms[0].key_arn]
    }
  }
}

# Note: AWSGlueServiceRole - which carries the EC2 ENI permissions Glue needs
# to run inside a VPC - is already attached to this same role by
# module.iam.aws_iam_role_policy_attachment.glue_service_role. It is
# deliberately not re-attached here; two Terraform resources managing one
# attachment would fight over it.

resource "aws_iam_role_policy" "glue_policy" {
  name   = "${aws_iam_role.glue_role.name}-policy"
  role   = aws_iam_role.glue_role.id
  policy = data.aws_iam_policy_document.glue_policy.json
}

