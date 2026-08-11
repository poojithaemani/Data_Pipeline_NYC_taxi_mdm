variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "Region the pipeline runs in. Passed explicitly so the IAM resource ARNs do not depend on provider-version-specific data source attributes."
  type        = string
}

variable "state_machine_name" {
  description = "Name of the pipeline state machine. Passed in from the root module so the monitoring module can build alarms against the same name without creating a dependency cycle."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for the state machine log group"
  type        = number
  default     = 30
}

############################################
# Glue stages
#
# Job names are passed in rather than constructed, so the state machine can
# never silently point at a differently named job.
############################################

variable "silver_job_name" {
  description = "Glue job name for the Bronze -> Silver stage"
  type        = string
}

variable "gold_job_name" {
  description = "Glue job name for the Silver -> Gold stage"
  type        = string
}

variable "golden_zone_job_name" {
  description = "Glue job name for the Golden Zone (MDM/SCD2) stage"
  type        = string
}

variable "warehouse_export_job_name" {
  description = "Glue job name for the warehouse Parquet export stage"
  type        = string
}

############################################
# Redshift COPY stage
############################################

variable "redshift_workgroup_name" {
  description = "Existing Redshift Serverless workgroup to run the COPY against. Looked up read-only; never created or modified here."
  type        = string
}

variable "redshift_database" {
  description = "Redshift database holding the star schema"
  type        = string
}

variable "copy_sql_path" {
  description = "Path to services/redshift/load/02_copy_from_s3.sql. That file is the single source of truth for the load; its statements are read at plan time and passed to the Redshift Data API."
  type        = string
}

variable "redshift_poll_seconds" {
  description = "Interval between Redshift Data API status polls. The measured COPY takes about 15 seconds in total."
  type        = number
  default     = 10
}

############################################
# QuickSight SPICE stage
############################################

variable "quicksight_dataset_id" {
  description = "Existing SPICE dataset to refresh. The dataset, analysis, dashboard and VPC connection are all left untouched."
  type        = string
}

variable "spice_poll_seconds" {
  description = "Interval between QuickSight ingestion status polls. The measured ingestion takes about 74 seconds."
  type        = number
  default     = 20
}

############################################
# Failure handling
############################################

variable "sns_topic_arn" {
  description = "SNS topic the Catch handler publishes to. Created by the monitoring module."
  type        = string
}

variable "pipeline_timeout_seconds" {
  description = "Overall execution timeout. Measured full pipeline is roughly 10 minutes of Glue plus ~2 minutes of load and refresh; the default leaves generous headroom without letting a stuck execution run indefinitely."
  type        = number
  default     = 5400
}
