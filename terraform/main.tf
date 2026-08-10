module "s3" {
  source = "./modules/s3"

  bucket_name  = var.bucket_name
  project_name = var.project_name
  environment  = var.environment
}

module "iam" {
  source = "./modules/iam"

  bucket_name  = var.bucket_name
  project_name = var.project_name
  environment  = var.environment
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name = var.project_name
  environment  = var.environment

  log_retention_days = var.log_retention_days
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

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  source_security_group_id = var.source_security_group_id

  database_name   = var.database_name
  master_username = var.master_username
  master_password = var.master_password

  allocated_storage = var.allocated_storage
  instance_class    = var.instance_class
}
