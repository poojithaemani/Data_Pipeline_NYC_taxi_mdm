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

variable "master_password" {
  description = "Master password for the RDS instance. Required only when create_rds is true."
  type        = string
  sensitive   = true
  default     = ""
  # Require a non-empty password only when RDS is being created
  validation {
    condition     = var.create_rds ? length(trimspace(var.master_password)) > 0 : true
    error_message = "master_password must be provided when create_rds is true"
  }
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

variable "enable_kms_for_athena" {
  type    = bool
  default = false
}

variable "kms_key_id" {
  type    = string
  default = ""
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
