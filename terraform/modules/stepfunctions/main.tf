############################################
# Pipeline orchestration - AWS Step Functions
#
# Additive module. It creates a state machine, its execution role and its log
# group, and nothing else. Every resource it orchestrates already exists and is
# referenced by name only:
#
#   - the four Glue jobs are started, never redefined
#   - the Redshift Serverless workgroup is looked up read-only
#   - the QuickSight dataset is refreshed, never recreated
#
# In particular this module adds no security group rules. The QuickSight
# ingress rule on the Redshift security group lives outside Terraform and must
# not be disturbed.
############################################

data "aws_caller_identity" "current" {}

# Read-only lookup. The workgroup is owned by modules/redshift, which is frozen;
# this only resolves its ARN so the Data API permissions can be scoped to it.
data "aws_redshiftserverless_workgroup" "this" {
  workgroup_name = var.redshift_workgroup_name
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  glue_job_names = [
    var.silver_job_name,
    var.gold_job_name,
    var.golden_zone_job_name,
    var.warehouse_export_job_name,
  ]

  # services/redshift/load/02_copy_from_s3.sql stays authoritative for the
  # load. It is read here and split into individual statements for the Data
  # API's batch call rather than being restated in Terraform, so the file and
  # the orchestration can never drift apart.
  #
  # The file contains only line comments, so stripping "--" to end-of-line is
  # sufficient; there are no string literals that could contain a double dash.
  copy_sql_raw = file(var.copy_sql_path)

  copy_sql_stripped = replace(local.copy_sql_raw, "/(?m)^\\s*--.*$/", "")

  copy_statements = [
    for statement in split(";", local.copy_sql_stripped) :
    trimspace(statement)
    if trimspace(statement) != ""
  ]

  definition = templatefile("${path.module}/definition.json.tftpl", {
    state_machine_name        = var.state_machine_name
    pipeline_timeout_seconds  = var.pipeline_timeout_seconds
    silver_job_name           = var.silver_job_name
    gold_job_name             = var.gold_job_name
    golden_zone_job_name      = var.golden_zone_job_name
    warehouse_export_job_name = var.warehouse_export_job_name
    redshift_workgroup_name   = var.redshift_workgroup_name
    redshift_database         = var.redshift_database
    redshift_poll_seconds     = var.redshift_poll_seconds
    copy_statements_json      = jsonencode(local.copy_statements)
    aws_account_id            = local.account_id
    quicksight_dataset_id     = var.quicksight_dataset_id
    spice_poll_seconds        = var.spice_poll_seconds
    sns_topic_arn             = var.sns_topic_arn
  })
}

############################################
# Log group
#
# Step Functions writes vended logs here. Kept separate from the Glue log
# group so retention can be tuned independently.
############################################

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${var.state_machine_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

############################################
# State machine
#
# STANDARD, not EXPRESS: the pipeline runs for roughly twelve minutes, far
# beyond the five-minute Express ceiling, and it needs durable, inspectable
# execution history for the operational-tracking requirement.
############################################

resource "aws_sfn_state_machine" "pipeline" {
  name       = var.state_machine_name
  role_arn   = aws_iam_role.sfn.arn
  type       = "STANDARD"
  definition = local.definition

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Name        = var.state_machine_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  depends_on = [aws_iam_role_policy.sfn]
}
