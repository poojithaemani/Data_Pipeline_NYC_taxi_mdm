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
# The Step Functions COPY stage previously authenticated with its own IAM
# identity, which Redshift Serverless maps to the database user
# IAMR:nyc-taxi-mdm-platform-sfn-role. That user can be granted DML, but
# ANALYZE requires table or database ownership and is not grantable, so the
# load failed at ANALYZE. Authenticating as the namespace admin through a
# secret resolves that without transferring ownership of the warehouse tables
# and without making the orchestration role a superuser.
#
# Why the RDS secret exists
# -------------------------
# The Glue jobs previously received the database password as a --DB_PASSWORD
# job argument, which is readable by any principal holding glue:GetJob and is
# stored in the job definition indefinitely. They now receive only a secret
# ARN and fetch the credential at runtime.
#
# Secret content
# --------------
# Only the two keys the consumers require: username and password. Nothing
# else is stored, so a disclosure exposes no additional topology.
#
# Handling of the values
# ----------------------
# Both passwords are generated or supplied as sensitive values, are never
# emitted in an output, and appear in no source file. They ARE written to
# terraform.tfstate - the state file is local and gitignored and must
# continue to be treated as a secret-bearing artifact.
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

############################################
# RDS master
############################################

resource "aws_secretsmanager_secret" "rds_master" {
  name        = "${var.project_name}/rds/master"
  description = "PostgreSQL master credentials fetched at runtime by the database-facing Glue jobs"

  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Name        = "${var.project_name}-rds-master"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id

  secret_string = jsonencode({
    username = var.rds_master_username
    password = var.rds_master_password
  })
}
