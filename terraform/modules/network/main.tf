############################################
# Private egress path for Glue
#
# Why this module exists
# ----------------------
# Closing the RDS security group means Glue can no longer reach the database
# over its public endpoint, so the two database-facing Glue jobs must run
# inside the VPC. Once a Glue job has a connection it runs on ENIs with no
# public IP, so it needs its own egress path:
#
#   - S3 (Silver/Gold/warehouse data, job scripts, temp dir) via a gateway
#     endpoint, which is free and keeps that traffic off the NAT entirely
#   - the public internet via NAT, because both jobs declare
#     --additional-python-modules and pip-install pg8000 and pyarrow from
#     PyPI at job start. Without egress the jobs fail before they run a line
#     of user code.
#
# The three existing default-VPC subnets route 0.0.0.0/0 to an internet
# gateway, which is useless to an ENI with no public address, so a genuinely
# private subnet is added rather than reusing them.
#
# Nothing existing is modified: no change to the VPC, the existing subnets,
# the main route table, or the Redshift security group whose out-of-band
# QuickSight ingress rule must survive.
############################################

resource "aws_subnet" "private" {
  vpc_id            = var.vpc_id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-private-${var.availability_zone}"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-nat-eip"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.nat_public_subnet_id

  tags = {
    Name        = "${var.project_name}-nat"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  tags = {
    Name        = "${var.project_name}-private-rt"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Gateway endpoint, not interface: it is free, and it keeps the bulk data
# path (2.85M trips of Parquet and Delta) off the metered NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name        = "${var.project_name}-s3-endpoint"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

############################################
# Security group for Glue ENIs
#
# AWS requires a Glue connection's security group to carry a self-referencing
# inbound rule covering all traffic - the job's ENIs talk to each other. That
# rule is scoped to this group only; it grants nothing to anything else.
############################################

resource "aws_security_group" "glue" {
  name        = "${var.project_name}-glue-sg"
  description = "Security group for Glue job ENIs running inside the VPC"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-glue-sg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "glue_self" {
  security_group_id = aws_security_group.glue.id
  description       = "Self-referencing rule required by AWS Glue for connection ENIs"

  referenced_security_group_id = aws_security_group.glue.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "glue_all" {
  security_group_id = aws_security_group.glue.id
  description       = "Outbound to S3 via the gateway endpoint, to PyPI via NAT, and to RDS"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

############################################
# Glue NETWORK connection
#
# A NETWORK connection carries no credentials - it only tells Glue which
# subnet and security group to place job ENIs in. Database credentials come
# from Secrets Manager at runtime.
############################################

resource "aws_glue_connection" "vpc" {
  name            = "${var.project_name}-vpc"
  description     = "Places database-facing Glue jobs inside the VPC so they can reach the private RDS instance"
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = aws_subnet.private.availability_zone
    subnet_id              = aws_subnet.private.id
    security_group_id_list = [aws_security_group.glue.id]
  }
}
