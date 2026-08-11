variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where RDS will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Private/Public subnet IDs for RDS subnet group"
  type        = list(string)
}

variable "source_security_group_id" {
  description = "The ID of the security group to allow ingress from."
  type        = string
}

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "master_username" {
  description = "Master username"
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "Master password"
  type        = string
  sensitive   = true
}

variable "allocated_storage" {
  description = "Allocated storage (GB)"
  type        = number
  default     = 20
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# ----------------------------------------------------------------------------
# Security phase additions
# ----------------------------------------------------------------------------

variable "backup_retention_period" {
  description = "Days of automated backups. Was hardcoded to 0, meaning the MDM database had no backups at all."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Guard against an accidental destroy of the MDM database."
  type        = bool
  default     = true
}
