variable "bucket_name" {
  description = "Name of the S3 Data Lake bucket"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}
variable "kms_key_arn" {
  description = "Customer managed KMS key for bucket default encryption. Empty keeps the previous SSE-S3 behaviour, so the change is reversible without touching stored objects."
  type        = string
  default     = ""
}
