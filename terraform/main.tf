module "s3" {
  source = "./modules/s3"

  bucket_name  = var.bucket_name
  project_name = var.project_name
  environment  = var.environment

  # Security phase: default encryption moves from SSE-S3 to the CMK. Applies
  # to new objects only, so existing data stays readable untouched.
  kms_key_arn = var.create_kms ? module.kms[0].key_arn : ""
}

module "redshift" {
  count  = var.create_redshift ? 1 : 0
  source = "./modules/redshift"

  project_name = var.project_name
  environment  = var.environment

  vpc_id     = var.vpc_id
  subnet_ids = var.redshift_subnet_ids

  bucket_name = var.bucket_name

  namespace_name = var.redshift_namespace_name
  workgroup_name = var.redshift_workgroup_name
  database_name  = var.redshift_database_name
  iam_role_name  = var.redshift_iam_role_name

  admin_username = var.redshift_admin_username
  admin_password = var.redshift_admin_password

  base_capacity       = var.redshift_base_capacity
  publicly_accessible = var.redshift_publicly_accessible
}

module "rds" {
  count  = var.create_rds ? 1 : 0
  source = "./modules/rds"

  project_name = var.project_name
  environment  = var.environment

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Security phase: ingress was 0.0.0.0/0. It is now the Glue security group,
  # which is the only consumer once the database is private.
  source_security_group_id = var.create_network ? module.network[0].glue_security_group_id : var.source_security_group_id

  database_name   = var.database_name
  master_username = var.master_username

  # Security phase: rotated. Generated at apply time rather than read from
  # tfvars, so the credential never lands in a file.
  master_password = random_password.rds_master.result

  backup_retention_period = var.rds_backup_retention_period
  deletion_protection     = var.rds_deletion_protection

  allocated_storage = var.allocated_storage
  instance_class    = var.instance_class
}

############################################
# Secrets
#
# Holds the Redshift admin credential that the Redshift Data API calls
# authenticate with. Retained through the NYC decommissioning because the
# Redshift workgroup outlives the pipeline that introduced it.
############################################

module "secrets" {
  count  = var.create_secrets ? 1 : 0
  source = "./modules/secrets"

  project_name = var.project_name
  environment  = var.environment

  # Guarded: create_kms and create_secrets are independent flags since the
  # decommissioning split them apart, so this index is reachable with the key
  # absent. Falling back to null lets Secrets Manager use its AWS-managed key
  # rather than failing the plan on an invalid index.
  kms_key_id = var.create_kms ? module.kms[0].key_arn : null

  redshift_admin_username = var.redshift_admin_username
  redshift_admin_password = var.redshift_admin_password
}
