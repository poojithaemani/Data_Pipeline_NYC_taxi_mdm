############################################
# Secrets Manager - Redshift admin credentials
#
# Additive module. It creates one secret and one version, and nothing else.
# The frozen modules/redshift is untouched: the Redshift namespace still owns
# the admin credential, and this secret simply carries a copy that the Redshift
# Data API can authenticate with.
#
# Why this exists
# ---------------
# The Step Functions COPY stage previously authenticated with its own IAM
# identity, which Redshift Serverless maps to the database user
# IAMR:nyc-taxi-mdm-platform-sfn-role. That user can be granted DML, but
# ANALYZE requires table or database ownership and is not grantable, so the
# load failed at ANALYZE. Authenticating as the namespace admin through a
# secret resolves that without transferring ownership of the warehouse tables
# and without making the orchestration role a superuser.
#
# Secret content
# --------------
# Only the two keys the Redshift Data API requires: username and password.
# Nothing else is stored, so the blast radius of a disclosure is limited to
# the Redshift admin credential that already exists.
#
# Handling of the value
# ---------------------
# The password arrives from terraform.tfvars, which is gitignored. It is
# marked sensitive end to end, is never emitted in an output, and appears in
# no source file. It IS written to terraform.tfstate, exactly as the RDS and
# Redshift admin passwords already are - the state file is local and gitignored
# and must continue to be treated as a secret-bearing artifact.
############################################

resource "aws_secretsmanager_secret" "redshift_admin" {
  name        = "${var.project_name}/redshift/admin"
  description = "Redshift Serverless admin credentials used by the pipeline state machine's Redshift Data API calls"

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
