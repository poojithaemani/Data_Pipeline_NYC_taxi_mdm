variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "redshift_admin_username" {
  description = "Redshift Serverless admin username stored in the secret"
  type        = string
}

variable "redshift_admin_password" {
  description = "Redshift Serverless admin password stored in the secret. Sourced from terraform.tfvars, which is gitignored; never hardcode it and never surface it in an output."
  type        = string
  sensitive   = true
}

variable "recovery_window_in_days" {
  description = "Deletion recovery window. Set to 7 rather than the 30 day default so the secret name can be reused promptly if the layer is torn down and rebuilt; 0 would delete immediately with no recovery and is deliberately not used."
  type        = number
  default     = 7
}
