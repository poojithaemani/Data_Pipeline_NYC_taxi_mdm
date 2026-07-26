module "s3" {
  source = "./modules/s3"

  bucket_name = var.bucket_name
  project_name = var.project_name
  environment = var.environment
}

module "iam" {
  source = "./modules/iam"

  bucket_name = var.bucket_name
  project_name = var.project_name
  environment = var.environment
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name = var.project_name
  environment  = var.environment

  log_retention_days = var.log_retention_days
}

module "rds" {
  source = "./modules/rds"

  project_name = var.project_name
  environment  = var.environment

  vpc_id              = var.vpc_id
  subnet_ids          = var.subnet_ids
  allowed_cidr_blocks = var.allowed_cidr_blocks

  database_name   = var.database_name
  master_username = var.master_username
  master_password = var.master_password

  allocated_storage = var.allocated_storage
  instance_class    = var.instance_class
}
