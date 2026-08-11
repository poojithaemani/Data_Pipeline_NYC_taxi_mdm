locals {
  # Shared by the stepfunctions and monitoring modules. The monitoring module
  # builds alarms against the state machine while the state machine publishes
  # to the monitoring module's SNS topic, so the name is passed to both as a
  # plain string rather than as a module output - otherwise the two modules
  # would form a dependency cycle.
  state_machine_name = "${var.project_name}-pipeline"

  pipeline_glue_job_names = [
    aws_glue_job.silver_etl.name,
    aws_glue_job.gold_etl.name,
    aws_glue_job.golden_zone_etl.name,
    aws_glue_job.warehouse_export_etl.name,
  ]
}

module "s3" {
  source = "./modules/s3"

  bucket_name  = var.bucket_name
  project_name = var.project_name
  environment  = var.environment
}

module "iam" {
  source = "./modules/iam"

  bucket_name  = var.bucket_name
  project_name = var.project_name
  environment  = var.environment
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name = var.project_name
  environment  = var.environment

  log_retention_days = var.log_retention_days
}

module "redshift" {
  count  = var.create_redshift ? 1 : 0
  source = "./modules/redshift"

  project_name = var.project_name
  environment  = var.environment

  vpc_id     = var.vpc_id
  subnet_ids = var.redshift_subnet_ids

  bucket_name = var.bucket_name

  namespace_name = var.redshift_namespace_name
  workgroup_name = var.redshift_workgroup_name
  database_name  = var.redshift_database_name
  iam_role_name  = var.redshift_iam_role_name

  admin_username = var.redshift_admin_username
  admin_password = var.redshift_admin_password

  base_capacity       = var.redshift_base_capacity
  publicly_accessible = var.redshift_publicly_accessible
}

module "rds" {
  count  = var.create_rds ? 1 : 0
  source = "./modules/rds"

  project_name = var.project_name
  environment  = var.environment

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  source_security_group_id = var.source_security_group_id

  database_name   = var.database_name
  master_username = var.master_username
  master_password = var.master_password

  allocated_storage = var.allocated_storage
  instance_class    = var.instance_class
}

############################################
# Orchestration and observability
#
# Both modules are additive. Monitoring is declared first because it owns the
# alerts topic that the state machine's failure handler publishes to.
############################################

module "monitoring" {
  count  = var.create_orchestration ? 1 : 0
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  state_machine_name      = local.state_machine_name
  glue_job_names          = local.pipeline_glue_job_names
  redshift_workgroup_name = var.redshift_workgroup_name

  alert_email = var.alert_email

  pipeline_duration_alarm_ms         = var.pipeline_duration_alarm_ms
  glue_failed_tasks_threshold        = var.glue_failed_tasks_threshold
  redshift_compute_seconds_threshold = var.redshift_compute_seconds_threshold
}

module "stepfunctions" {
  count  = var.create_orchestration ? 1 : 0
  source = "./modules/stepfunctions"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  state_machine_name = local.state_machine_name
  log_retention_days = var.log_retention_days

  silver_job_name           = aws_glue_job.silver_etl.name
  gold_job_name             = aws_glue_job.gold_etl.name
  golden_zone_job_name      = aws_glue_job.golden_zone_etl.name
  warehouse_export_job_name = aws_glue_job.warehouse_export_etl.name

  redshift_workgroup_name = var.redshift_workgroup_name
  redshift_database       = var.redshift_database_name

  # The load SQL stays the single source of truth; it is read, not restated.
  copy_sql_path = "${path.root}/../services/redshift/load/02_copy_from_s3.sql"

  quicksight_dataset_id = var.quicksight_dataset_id

  redshift_poll_seconds    = var.redshift_poll_seconds
  spice_poll_seconds       = var.spice_poll_seconds
  pipeline_timeout_seconds = var.pipeline_timeout_seconds

  sns_topic_arn = module.monitoring[0].alerts_topic_arn
}
