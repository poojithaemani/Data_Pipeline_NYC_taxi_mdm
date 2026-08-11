############################################
# Security Group for PostgreSQL
############################################

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for PostgreSQL RDS"
  vpc_id      = var.vpc_id

  # Security phase: this was cidr_blocks = ["0.0.0.0/0"], which exposed
  # PostgreSQL to the entire internet. Ingress is now restricted to the Glue
  # security group, which is the only thing that needs to reach the database.
  # That is possible because the database-facing Glue jobs now run inside the
  # VPC via a NETWORK connection rather than over the public endpoint.
  ingress {
    description     = "PostgreSQL from Glue job ENIs only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.source_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

############################################
# DB Subnet Group
############################################

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Project     = var.project_name
    Environment = var.environment
  }
}

############################################
# Parameter Group
############################################

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project_name}-postgres-parameter-group"
  family = "postgres17"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # Security phase: reject any connection that is not TLS. The Glue jobs pass
  # an explicit ssl_context to pg8000, which does not negotiate TLS on its
  # own. Certificate verification is deliberately not enforced client-side
  # yet - that needs the RDS CA bundle staged for the job, which is tracked
  # as a follow-up; the connection is encrypted either way.
  #
  # apply_method must be stated explicitly. rds.force_ssl only takes effect
  # after a reboot, so AWS records it as pending-reboot while the provider
  # defaults an unstated apply_method to "immediate" - which makes the two
  # disagree on every plan and the resource never converges. This is the same
  # class of perpetual drift as the Redshift workgroup config_parameter set.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

############################################
# PostgreSQL RDS Instance
############################################

resource "aws_db_instance" "postgres" {

  identifier = "${var.project_name}-postgres"

  engine         = "postgres"
  engine_version = "17.9"

  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100

  db_name  = var.database_name
  username = var.master_username
  password = var.master_password

  port = 5432

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  parameter_group_name = aws_db_parameter_group.postgres.name

  storage_encrypted = true

  # Security phase: was true, which put the instance on a public IP. Glue now
  # reaches it privately through the VPC connection, so nothing needs the
  # public endpoint.
  #
  # Consequence, deliberately accepted: the database is no longer reachable
  # from a workstation. scripts/sync_pipeline_runs.py must run from inside
  # the VPC from now on.
  publicly_accessible = false

  multi_az = false

  skip_final_snapshot = true

  # Security phase: was 0, meaning no backups existed at all and any data
  # loss was unrecoverable.
  backup_retention_period = var.backup_retention_period

  # Security phase: was false, so a stray destroy could delete the MDM
  # database outright.
  deletion_protection = var.deletion_protection

  auto_minor_version_upgrade = true

  apply_immediately = true

  tags = {
    Name        = "${var.project_name}-postgres"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}