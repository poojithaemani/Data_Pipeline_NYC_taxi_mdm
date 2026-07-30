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
  description = "The ID of the security group to allow ingress from."
  type        = string
}

variable "database_name" {
  type = string
}

variable "master_username" {
  type      = string
  sensitive = true
}

variable "master_password" {
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

