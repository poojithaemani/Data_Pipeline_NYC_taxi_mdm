############################################
# IAM Role for Redshift Serverless
#
# Dedicated role - deliberately not reusing the Glue/Lambda/EventBridge
# roles so Redshift permissions can be reasoned about independently.
############################################

data "aws_iam_policy_document" "redshift_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type = "Service"
      # Redshift Serverless assumes the role via the redshift-serverless
      # principal; the redshift principal is required for COPY/UNLOAD and
      # for the role to be usable from within the database.
      identifiers = [
        "redshift.amazonaws.com",
        "redshift-serverless.amazonaws.com"
      ]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "redshift" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.redshift_assume_role.json
}

############################################
# Least-privilege S3 policy
#
# Scoped to the project data lake bucket only. AWS managed policies such as
# AmazonRedshiftAllCommandsFullAccess are intentionally NOT attached: they
# grant broad access across S3, Glue, Athena, SageMaker and Lambda for
# features this project does not use. Additional permissions (UNLOAD writes,
# Glue Catalog access for Spectrum) will be added only when those features
# are actually implemented.
############################################

data "aws_iam_policy_document" "redshift_s3" {
  statement {
    sid    = "S3BucketList"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = ["arn:aws:s3:::${var.bucket_name}"]
  }

  statement {
    sid    = "S3ObjectRead"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]

    resources = ["arn:aws:s3:::${var.bucket_name}/*"]
  }
}

resource "aws_iam_policy" "redshift_s3" {
  name        = "${var.iam_role_name}-s3-policy"
  description = "Read-only access to the ${var.bucket_name} data lake for Redshift Serverless"
  policy      = data.aws_iam_policy_document.redshift_s3.json
}

resource "aws_iam_role_policy_attachment" "redshift_s3" {
  role       = aws_iam_role.redshift.name
  policy_arn = aws_iam_policy.redshift_s3.arn
}

############################################
# Security Group for Redshift Serverless
#
# Dedicated group in the existing VPC. No ingress rules: the workgroup is
# not publicly accessible and initial access is via Query Editor v2, which
# does not traverse this security group.
############################################

resource "aws_security_group" "redshift" {
  name        = "${var.project_name}-redshift-sg"
  description = "Security group for Redshift Serverless workgroup"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-redshift-sg"
  }
}

############################################
# Redshift Serverless Namespace
#
# Storage-level container: database, credentials and IAM roles.
# Encryption is enabled by default using an AWS-managed key; no customer
# managed KMS key is configured, matching the rest of the project.
############################################

resource "aws_redshiftserverless_namespace" "this" {
  namespace_name = var.namespace_name

  db_name        = var.database_name
  admin_username = var.admin_username

  admin_user_password = var.admin_password

  iam_roles            = [aws_iam_role.redshift.arn]
  default_iam_role_arn = aws_iam_role.redshift.arn

  tags = {
    Name = var.namespace_name
  }

  depends_on = [aws_iam_role_policy_attachment.redshift_s3]
}

############################################
# Redshift Serverless Workgroup
#
# Compute-level container. Base capacity is the minimum valid value of
# 8 RPUs. Placed in the existing VPC subnets across three AZs, which
# Redshift Serverless requires.
############################################

resource "aws_redshiftserverless_workgroup" "this" {
  workgroup_name = var.workgroup_name
  namespace_name = aws_redshiftserverless_namespace.this.namespace_name

  base_capacity = var.base_capacity

  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.redshift.id]

  publicly_accessible = var.publicly_accessible

  config_parameter {
    parameter_key   = "require_ssl"
    parameter_value = "true"
  }

  tags = {
    Name = var.workgroup_name
  }
}
