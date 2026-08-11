############################################
# Execution role for the pipeline state machine
#
# Dedicated role, deliberately not reusing the Glue, Lambda or EventBridge
# roles so the orchestration permissions can be reasoned about on their own.
############################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.project_name}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name        = "${var.project_name}-sfn-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "sfn" {

  # Glue .sync integration polls the job run; it does not use EventBridge
  # managed rules, so no events:* permissions are required here.
  statement {
    sid    = "GlueJobRuns"
    effect = "Allow"

    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun",
    ]

    resources = [
      for job in local.glue_job_names :
      "arn:aws:glue:${var.aws_region}:${local.account_id}:job/${job}"
    ]
  }

  # Statement submission is scoped to the one workgroup that holds the star
  # schema.
  statement {
    sid    = "RedshiftDataExecute"
    effect = "Allow"

    actions = [
      "redshift-data:BatchExecuteStatement",
      "redshift-data:ExecuteStatement",
    ]

    resources = [data.aws_redshiftserverless_workgroup.this.arn]
  }

  # DescribeStatement / GetStatementResult / CancelStatement are not
  # resource-scopable in IAM: they are authorised against the statement, not
  # the workgroup. AWS scopes them with a statement-owner condition instead.
  statement {
    sid    = "RedshiftDataStatus"
    effect = "Allow"

    actions = [
      "redshift-data:DescribeStatement",
      "redshift-data:GetStatementResult",
      "redshift-data:CancelStatement",
    ]

    resources = ["*"]
  }

  # Required for the Data API to obtain temporary credentials for the
  # workgroup using this role's identity.
  statement {
    sid    = "RedshiftServerlessCredentials"
    effect = "Allow"

    actions = ["redshift-serverless:GetCredentials"]

    resources = [data.aws_redshiftserverless_workgroup.this.arn]
  }

  # Refresh only. No permission to create, update or delete the dataset, the
  # analysis, the dashboard or the VPC connection.
  statement {
    sid    = "QuickSightIngestion"
    effect = "Allow"

    actions = [
      "quicksight:CreateIngestion",
      "quicksight:DescribeIngestion",
      "quicksight:CancelIngestion",
    ]

    resources = [
      "arn:aws:quicksight:${var.aws_region}:${local.account_id}:dataset/${var.quicksight_dataset_id}",
      "arn:aws:quicksight:${var.aws_region}:${local.account_id}:dataset/${var.quicksight_dataset_id}/ingestion/*",
    ]
  }

  statement {
    sid       = "PublishFailureNotifications"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }

  # Step Functions vended logs. The log-delivery APIs are not resource-scopable.
  statement {
    sid    = "StateMachineLogging"
    effect = "Allow"

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "${aws_iam_role.sfn.name}-policy"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn.json
}
