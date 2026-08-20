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

variable "github_repository_immutable" {
  description = "The same repository in the ID-bearing form GitHub emits in the OIDC sub claim: owner@ownerid/repo@repoid. The numeric IDs are immutable, so a rename cannot be used to impersonate the repository. Both forms are accepted by the trust policies."
  type        = string
  default     = "poojithaemani@166465179/Data_Pipeline_NYC_taxi_mdm@1311315580"
}

variable "cicd_apply_environment" {
  description = "GitHub environment gating the apply role. Configure its required reviewers in repository settings."
  type        = string
  default     = "production"
}

################################################################################
# Retention flags
#
# Split out of create_orchestration during the NYC decommissioning. The
# encryption key and the secrets outlive the pipeline that introduced them:
# the data lake bucket's default encryption IS the CMK, so destroying the key
# alongside the orchestration layer would make every retained object in that
# bucket permanently unreadable. The Redshift admin secret is likewise still
# required by the retained Redshift workgroup.
################################################################################

variable "create_kms" {
  description = "Create the customer managed key. Retained independently of the orchestration layer because the retained S3 data lake is encrypted with it."
  type        = bool
  default     = true
}

variable "create_secrets" {
  description = "Create the Secrets Manager secrets. Retained independently of the orchestration layer because the retained Redshift workgroup authenticates through the admin secret."
  type        = bool
  default     = true
}

variable "create_network" {
  description = "Create the private egress path for VPC-bound Glue jobs: private subnet, NAT gateway, Elastic IP, S3 endpoint and the Glue connection. Renamed from create_orchestration during the NYC decommissioning, when the orchestration layer it also gated was removed. The NAT gateway bills hourly whenever this is true."
  type        = bool
  default     = true
}
