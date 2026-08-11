############################################
# Security phase
#
# Adds the customer managed key, the private egress path that lets Glue reach
# a non-public RDS instance, and the rotated database credential.
#
# Every resource here is additive. The one thing this file deliberately does
# NOT do is declare any ingress on the Redshift security group: the
# QuickSight connection depends on an ingress rule that lives outside
# Terraform, and adding an ingress block to that module would delete it.
############################################

############################################
# Rotated RDS master password
#
# Generated rather than supplied. The value therefore never exists in
# terraform.tfvars, in any source file, in a variable default, or in an
# output - only in terraform.tfstate (already gitignored and already
# secret-bearing) and in Secrets Manager.
#
# The excluded characters are the ones RDS rejects in a master password:
# forward slash, at sign, double quote and space.
############################################

resource "random_password" "rds_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?,."

  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

############################################
# Customer managed key
#
# The Step Functions role is intentionally absent from key_user_role_arns.
# It consumes the key only to decrypt a secret, and it is granted kms:Decrypt
# through its own inline policy instead - the key policy already delegates to
# the account root, so an IAM grant is sufficient. Referencing the state
# machine's role here would create a cycle, because the state machine depends
# on the secret, which depends on this key.
############################################

module "kms" {
  count  = var.create_orchestration ? 1 : 0
  source = "./modules/kms"

  project_name = var.project_name
  environment  = var.environment

  key_user_role_arns = compact([
    aws_iam_role.glue_role.arn,
    var.create_redshift ? module.redshift[0].iam_role_arn : "",
  ])
}

############################################
# Private egress path for Glue
############################################

module "network" {
  count  = var.create_orchestration ? 1 : 0
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_id = var.vpc_id

  # The NAT gateway must sit in a subnet that already routes to the internet
  # gateway; the private subnet this module creates is the one Glue runs in.
  nat_public_subnet_id = var.subnet_ids[0]
  availability_zone    = var.glue_private_subnet_az
  private_subnet_cidr  = var.glue_private_subnet_cidr
}
