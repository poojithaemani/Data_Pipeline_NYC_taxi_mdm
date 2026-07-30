variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "bucket_name" {
  description = "S3 Data Lake bucket name"
  type        = string
}

variable "query_results_prefix" {
  description = "Prefix for Athena query results"
  type        = string
  default     = "athena-query-results/"
}
