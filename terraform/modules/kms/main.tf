############################################
# Customer managed KMS key
#
# One key for the project's at-rest encryption. Scope is deliberate:
#
#   IN  - Secrets Manager secrets, S3 data-lake default encryption, Athena
#         query results. All three can adopt a CMK in place.
#
#   OUT - RDS storage and the Redshift namespace. Both are already encrypted
#         with AWS managed keys, and switching either to a CMK requires
#         replacing the resource (RDS needs a snapshot and restore). Replacing
#         a working, reconciled warehouse to change key ownership is not a
#         trade worth making here; it is recorded as accepted risk instead.
#
# S3 default encryption applies to NEW objects only, so existing SSE-S3
# objects stay readable throughout and no re-encryption backfill is needed.
############################################

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

data "aws_iam_policy_document" "key" {

  # Without this the key becomes unmanageable - IAM cannot grant access to a
  # key whose policy does not delegate to the account root.
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # The pipeline's service roles. Encrypt/decrypt and data-key generation
  # only - no key administration, no scheduling deletion.
  statement {
    sid    = "AllowPipelineRolesToUseTheKey"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.key_user_role_arns
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]
  }

  # Lets S3, Secrets Manager and Athena use the key on behalf of a caller who
  # is already authorised, without granting those services blanket access.
  statement {
    sid    = "AllowServiceUseViaViaGrants"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "s3.amazonaws.com",
        "secretsmanager.amazonaws.com",
        "athena.amazonaws.com",
      ]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "this" {
  description         = "Customer managed key for ${var.project_name} - Secrets Manager, S3 data lake and Athena results"
  enable_key_rotation = true

  # A deletion window is a safety net: anything encrypted with this key
  # becomes unreadable once it is gone.
  deletion_window_in_days = var.deletion_window_in_days

  policy = data.aws_iam_policy_document.key.json

  tags = {
    Name        = "${var.project_name}-cmk"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.this.key_id
}
