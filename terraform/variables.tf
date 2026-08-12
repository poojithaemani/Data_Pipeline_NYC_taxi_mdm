variable "aws_region" {
  description = "AWS Region"
  type        = string
}
variable "bucket_name" {
  type = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "source_security_group_id" {
  description = "The ID of the security group to allow ingress from. Required when create_rds = true."
  type        = string
  default     = ""
  # Require a value only when RDS is being created
  validation {
    condition     = var.create_rds ? length(trimspace(var.source_security_group_id)) > 0 : true
    error_message = "source_security_group_id must be provided when create_rds is true"
  }
}

variable "database_name" {
  type = string
}

variable "master_username" {
  type      = string
  sensitive = true
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

# Toggle creation of RDS resources in this root. When false, RDS module is skipped
# and RDS-specific variables are not required. Useful to plan/apply metadata-only changes.
variable "create_rds" {
  type        = bool
  default     = true
  description = "Whether to create RDS infrastructure"
}

################################################################################
# Redshift Serverless
#
# Reuses the existing VPC. redshift_subnet_ids is intentionally separate from
# subnet_ids (consumed by RDS) because Redshift Serverless requires subnets in
# at least three Availability Zones.
################################################################################

variable "create_redshift" {
  description = "Whether to create Redshift Serverless infrastructure"
  type        = bool
  default     = true
}

variable "redshift_subnet_ids" {
  description = "Subnet IDs for the Redshift Serverless workgroup. Must span at least three AZs."
  type        = list(string)
}

variable "redshift_namespace_name" {
  description = "Redshift Serverless namespace name"
  type        = string
  default     = "nyc-taxi-mdm"
}

variable "redshift_workgroup_name" {
  description = "Redshift Serverless workgroup name"
  type        = string
  default     = "nyc-taxi-mdm-wg"
}

variable "redshift_database_name" {
  description = "Initial database created in the Redshift Serverless namespace"
  type        = string
  default     = "taxi_analytics"
}

variable "redshift_iam_role_name" {
  description = "Name of the dedicated IAM role assumed by Redshift"
  type        = string
  default     = "nyc-taxi-mdm-redshift-role"
}

variable "redshift_admin_username" {
  description = "Redshift Serverless admin username"
  type        = string
  sensitive   = true
  default     = "redshift_admin"
}

variable "redshift_admin_password" {
  description = "Redshift Serverless admin password. Supplied via terraform.tfvars (gitignored)."
  type        = string
  sensitive   = true
}

variable "redshift_base_capacity" {
  description = "Base capacity in RPUs. Minimum valid value is 8."
  type        = number
  default     = 8
}

variable "redshift_publicly_accessible" {
  description = "Whether the Redshift Serverless workgroup is publicly accessible"
  type        = bool
  default     = false
}

# Glue catalog database names
variable "bronze_db_name" {
  type    = string
  default = "bronze_db"
}

variable "silver_db_name" {
  type    = string
  default = "silver_db"
}

variable "gold_db_name" {
  type    = string
  default = "gold_db"
}

variable "master_db_name" {
  type    = string
  default = "master_db"
}

# Glue crawlers
variable "bronze_crawler_name" {
  type    = string
  default = "bronze_crawler"
}

variable "silver_crawler_name" {
  type    = string
  default = "silver_crawler"
}

variable "gold_crawler_name" {
  type    = string
  default = "gold_crawler"
}

# Glue service role (optional). If empty, module will derive name from project_name at resource creation time.
variable "glue_role_name" {
  type    = string
  default = ""
}

# Athena configuration (workgroup name). If empty, a name will be derived from project_name
variable "athena_workgroup_name" {
  type    = string
  default = ""
}

variable "athena_results_prefix" {
  type    = string
  default = "athena-results/"
}

# S3 prefixes to grant crawler access to (can be extended)
variable "s3_data_prefixes" {
  type    = list(string)
  default = ["bronze/", "silver/", "gold/"]
}

# Glue Job Configuration
variable "glue_job_worker_type" {
  description = "The type of worker that your Glue job is configured to use."
  type        = string
  default     = "G.1X"
  validation {
    condition     = contains(["Standard", "G.1X", "G.2X", "G.025X", "Z.2X"], var.glue_job_worker_type)
    error_message = "Invalid Glue job worker type. Must be one of: Standard, G.1X, G.2X, G.025X, Z.2X."
  }
}

variable "glue_job_number_of_workers" {
  description = "The number of workers of a given worker type that are allocated to the job."
  type        = number
  default     = 2
  validation {
    condition     = var.glue_job_number_of_workers >= 1
    error_message = "Number of workers must be at least 1."
  }
}

# S3 Data Paths for Glue Job Arguments
variable "bronze_transactions_path" {
  description = "S3 path to the Bronze layer transactions (e.g., 'bronze/transactions/yellow_taxi/')."
  type        = string
  default     = "bronze/transactions/yellow_taxi/"
}

variable "bronze_reference_path" {
  description = "S3 path to the Bronze layer reference data (e.g., 'bronze/reference/')."
  type        = string
  default     = "bronze/reference/"
}

# Paths for Delta Lake tables, used by delta_target crawlers and Glue jobs
variable "silver_delta_table_path" {
  description = "S3 path suffix for the Silver layer Delta table (e.g., 'silver/yellow_taxi')."
  type        = string
  default     = "silver/yellow_taxi"
}

variable "gold_delta_table_path" {
  description = "S3 path suffix for the Gold layer Delta table (e.g., 'gold/yellow_taxi')."
  type        = string
  default     = "gold/yellow_taxi"
}

variable "warehouse_path" {
  description = "S3 path suffix for the Redshift-ready Parquet warehouse snapshot (e.g., 'warehouse')."
  type        = string
  default     = "warehouse"
}

# ----------------------------------------------------------------------------
# Orchestration and observability
#
# All additive. create_orchestration follows the create_rds / create_redshift
# pattern already used above, so the layer can be stood down without touching
# any other resource.
# ----------------------------------------------------------------------------

variable "create_orchestration" {
  description = "Create the Step Functions state machine and the CloudWatch/SNS monitoring layer."
  type        = bool
  default     = true
}

variable "quicksight_dataset_id" {
  description = "Existing QuickSight SPICE dataset refreshed at the end of the pipeline. Refreshed only - never created or modified by Terraform."
  type        = string
  default     = "nyc-taxi-trips-star"
}

variable "alert_email" {
  description = "Optional email subscribed to the alerts topic. Requires out-of-band confirmation of the emailed link."
  type        = string
  default     = ""
}

variable "redshift_poll_seconds" {
  description = "Interval between Redshift Data API status polls in the state machine."
  type        = number
  default     = 10
}

variable "spice_poll_seconds" {
  description = "Interval between QuickSight ingestion status polls in the state machine."
  type        = number
  default     = 20
}

variable "pipeline_timeout_seconds" {
  description = "Overall timeout for one state machine execution."
  type        = number
  default     = 5400
}

variable "pipeline_duration_alarm_ms" {
  description = "Alarm threshold for a single pipeline execution's duration, in milliseconds."
  type        = number
  default     = 2700000
}

variable "glue_failed_tasks_threshold" {
  description = "Reference line on the Glue task-failure dashboard chart. Not an alarm threshold - see terraform/modules/monitoring/main.tf for why CloudWatch cannot alarm on this metric."
  type        = number
  default     = 5
}

variable "redshift_compute_seconds_threshold" {
  description = "Daily RPU-second ceiling for the Redshift Serverless workgroup, used as a cost guard."
  type        = number
  default     = 43200
}

# ----------------------------------------------------------------------------
# Security phase
# ----------------------------------------------------------------------------

variable "glue_private_subnet_cidr" {
  description = "CIDR of the private subnet created for Glue ENIs. Must not overlap the default VPC's existing /20 subnets at 172.31.0.0, 172.31.16.0 and 172.31.32.0."
  type        = string
  default     = "172.31.128.0/20"
}

variable "glue_private_subnet_az" {
  description = "AZ for the Glue private subnet. Matches the NAT gateway's AZ to avoid cross-AZ data charges."
  type        = string
  default     = "us-east-2a"
}

variable "rds_backup_retention_period" {
  description = "Days of automated RDS backups. Was effectively 0 before the security phase."
  type        = number
  default     = 7
}

variable "rds_deletion_protection" {
  description = "Protect the MDM database from an accidental destroy."
  type        = bool
  default     = true
}

variable "demo_path" {
  description = "S3 prefix holding the isolated Delta time-travel demonstration. Kept separate from the medallion layers so the demo can never be confused with production data."
  type        = string
  default     = "demo"
}

# ----------------------------------------------------------------------------
# CI/CD - remote state and GitHub Actions OIDC
# ----------------------------------------------------------------------------

variable "tfstate_bucket_name" {
  description = "S3 bucket holding remote Terraform state. Must be globally unique; the account id keeps it so."
  type        = string
  default     = "nyc-taxi-mdm-platform-tfstate-749185461065"
}

variable "create_cicd" {
  description = "Create the GitHub Actions OIDC provider and its plan/apply roles."
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "owner/repo permitted to assume the CI roles. This is the security boundary for OIDC."
  type        = string
  default     = "poojithaemani/Data_Pipeline_NYC_taxi_mdm"
}

variable "cicd_apply_environment" {
  description = "GitHub environment gating the apply role. Configure its required reviewers in repository settings."
  type        = string
  default     = "production"
}
