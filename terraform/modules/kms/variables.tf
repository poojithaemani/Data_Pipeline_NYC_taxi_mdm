variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "key_user_role_arns" {
  description = "Service role ARNs granted encrypt/decrypt on the key. Glue reads and writes S3 objects, Redshift COPYs them, and Step Functions decrypts the Redshift secret."
  type        = list(string)
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion completes. Data encrypted with this key is unrecoverable once deletion finishes, so the maximum window is used."
  type        = number
  default     = 30
}
