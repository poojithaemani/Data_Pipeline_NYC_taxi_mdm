variable "project_name" {
  description = "Project name prefix. Also scopes which IAM principals the apply role may manage."
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "github_repository" {
  description = "owner/repo that may assume these roles. This value IS the security boundary - it becomes the sub claim condition in both trust policies."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be in owner/repo form, with no https:// prefix and no .git suffix."
  }
}

variable "plan_readable_secret_arns" {
  description = "Exact ARNs of the Terraform-managed Secrets Manager secrets the plan role may read. Terraform reads a secret's value on every refresh of aws_secretsmanager_secret_version, and GetSecretValue is excluded from the ReadOnlyAccess managed policy because it returns credential material. Listed explicitly - never a wildcard. Empty grants nothing."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.plan_readable_secret_arns : can(regex("^arn:[a-z-]+:secretsmanager:", a))])
    error_message = "plan_readable_secret_arns must contain full Secrets Manager ARNs."
  }
}

variable "plan_readable_glue_connection_arn" {
  description = "Exact ARN of the Terraform-managed Glue connection the plan role may read. glue:GetConnection is excluded from ReadOnlyAccess because a JDBC connection can carry a password. Empty grants nothing."
  type        = string
  default     = ""

  validation {
    condition     = var.plan_readable_glue_connection_arn == "" || can(regex("^arn:[a-z-]+:glue:[a-z0-9-]+:[0-9]+:connection/", var.plan_readable_glue_connection_arn))
    error_message = "plan_readable_glue_connection_arn must be empty or a full Glue connection ARN."
  }
}

variable "github_repository_immutable" {
  description = "Same repository in the ID-bearing form GitHub now emits in the OIDC sub claim - owner@ownerid/repo@repoid. Accepted alongside github_repository so the trust policy matches whichever form GitHub sends. Empty to accept only the classic form."
  type        = string
  default     = ""

  validation {
    condition     = var.github_repository_immutable == "" || can(regex("^[A-Za-z0-9._-]+@[0-9]+/[A-Za-z0-9._-]+@[0-9]+$", var.github_repository_immutable))
    error_message = "github_repository_immutable must be empty or in owner@ownerid/repo@repoid form."
  }
}

variable "apply_environment" {
  description = "GitHub environment whose required reviewers gate the apply role. The name appears in the sub claim, so approval is enforced by the AWS trust policy, not just by workflow convention."
  type        = string
  default     = "production"
}

variable "tfstate_bucket_name" {
  description = "Remote state bucket the roles are granted access to"
  type        = string
}

variable "kms_key_arn" {
  description = "Project customer managed key. The plan role needs kms:Decrypt to refresh KMS-encrypted resources."
  type        = string
}

variable "iam_secondary_prefix" {
  description = "Second IAM name prefix the apply role may manage. The Redshift role is named nyc-taxi-mdm-* rather than nyc-taxi-mdm-platform-*, so the project prefix alone does not cover it."
  type        = string
}

variable "thumbprint_list" {
  description = "Root CA thumbprints for the GitHub OIDC endpoint. AWS no longer validates these for token.actions.githubusercontent.com, but the resource still requires the field."
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}
