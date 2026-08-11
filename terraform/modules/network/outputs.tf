output "glue_security_group_id" {
  description = "Security group attached to Glue job ENIs. The RDS security group grants ingress to this group instead of to the internet."
  value       = aws_security_group.glue.id
}

output "glue_connection_name" {
  description = "Glue NETWORK connection name to attach to database-facing jobs"
  value       = aws_glue_connection.vpc.name
}

output "private_subnet_id" {
  description = "Private subnet hosting Glue ENIs"
  value       = aws_subnet.private.id
}

output "nat_gateway_id" {
  description = "NAT gateway providing outbound internet for pip installs"
  value       = aws_nat_gateway.this.id
}

output "nat_public_ip" {
  description = "Elastic IP of the NAT gateway"
  value       = aws_eip.nat.public_ip
}

output "s3_vpc_endpoint_id" {
  description = "S3 gateway endpoint keeping data-lake traffic off the NAT"
  value       = aws_vpc_endpoint.s3.id
}

output "private_route_table_id" {
  description = "Route table for the private subnet"
  value       = aws_route_table.private.id
}
