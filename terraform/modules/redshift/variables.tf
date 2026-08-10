variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the Redshift Serverless workgroup will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the Redshift Serverless workgroup. Redshift Serverless requires subnets in at least three Availability Zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 3
    error_message = "Redshift Serverless requires at least 3 subnets in different Availability Zones."
  }
}

variable "bucket_name" {
  description = "S3 data lake bucket the Redshift role is granted read access to"
  type        = string
}

variable "namespace_name" {
  description = "Redshift Serverless namespace name"
  type        = string
}

variable "workgroup_name" {
  description = "Redshift Serverless workgroup name"
  type        = string
}

variable "database_name" {
  description = "Initial database created in the namespace"
  type        = string
}

variable "admin_username" {
  description = "Redshift Serverless admin username"
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "Redshift Serverless admin password"
  type        = string
  sensitive   = true
}

variable "base_capacity" {
  description = "Base capacity in RPUs. Redshift Serverless requires a minimum of 8, in increments of 8."
  type        = number
  default     = 8

  validation {
    condition     = var.base_capacity >= 8 && var.base_capacity % 8 == 0
    error_message = "base_capacity must be at least 8 and a multiple of 8."
  }
}

variable "iam_role_name" {
  description = "Name of the dedicated IAM role assumed by Redshift"
  type        = string
}

variable "publicly_accessible" {
  description = "Whether the workgroup is reachable from the public internet. Kept false; use Query Editor v2 for access."
  type        = bool
  default     = false
}
