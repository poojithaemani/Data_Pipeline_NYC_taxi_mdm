############################################
# Security Group for PostgreSQL
############################################

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for PostgreSQL RDS"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

  publicly_accessible = true

  multi_az = false

  skip_final_snapshot = true

  backup_retention_period = 0

  deletion_protection = false

  auto_minor_version_upgrade = true

  apply_immediately = true

  tags = {
    Name        = "${var.project_name}-postgres"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}