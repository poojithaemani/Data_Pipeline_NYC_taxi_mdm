output "db_instance_id" {
  description = "RDS Instance ID"
  value       = aws_db_instance.postgres.id
}

output "db_instance_identifier" {
  description = "RDS Instance Identifier"
  value       = aws_db_instance.postgres.identifier
}

output "db_endpoint" {
  description = "PostgreSQL Endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "db_address" {
  description = "PostgreSQL Address"
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "PostgreSQL Port"
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "Database Name"
  value       = aws_db_instance.postgres.db_name
}

output "db_security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.rds_sg.id
}

output "db_subnet_group" {
  description = "DB Subnet Group"
  value       = aws_db_subnet_group.rds_subnet_group.name
}

output "parameter_group" {
  description = "DB Parameter Group"
  value       = aws_db_parameter_group.postgres.name
}