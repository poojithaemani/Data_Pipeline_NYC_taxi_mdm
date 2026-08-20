############################################
# Secrets Manager - database credentials
#
# Additive module. It creates secrets and their versions, and nothing else.
# The frozen modules/redshift is untouched: the Redshift namespace still owns
# the admin credential, and this secret simply carries a copy that the
# Redshift Data API can authenticate with.
#
# Why the Redshift secret exists
# ------------------------------
# A caller authenticating to Redshift with its own IAM identity is mapped to a
# database user that can be granted DML, but ANALYZE requires table or database
# ownership and is not grantable - so a load fails at ANALYZE. Authenticating
# as the namespace admin through this secret resolves that without transferring
# ownership of the warehouse tables and without making any orchestration role a
# superuser.
#
# The RDS master secret was removed during the NYC decommissioning, along with
# the database it belonged to and the Glue jobs that fetched it at runtime. Its
# definition is recoverable from git history if RDS is ever rebuilt.
#
# Secret content
# --------------
# Only the two keys the consumer requires: username and password. Nothing else
# is stored, so a disclosure exposes no additional topology.
#
# Handling of the values
# ----------------------
# The password is supplied as a sensitive value, is never emitted in an output,
# and appears in no source file. It IS written to terraform.tfstate - the state
# lives in a private, versioned S3 bucket and must continue to be treated as a
# secret-bearing artifact.
############################################

############################################
# Redshift admin
############################################

resource "aws_secretsmanager_secret" "redshift_admin" {
  name        = "${var.project_name}/redshift/admin"
  description = "Redshift Serverless admin credentials used by the pipeline state machine's Redshift Data API calls"

  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Name        = "${var.project_name}-redshift-admin"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "redshift_admin" {
  secret_id = aws_secretsmanager_secret.redshift_admin.id

  secret_string = jsonencode({
    username = var.redshift_admin_username
    password = var.redshift_admin_password
  })
}