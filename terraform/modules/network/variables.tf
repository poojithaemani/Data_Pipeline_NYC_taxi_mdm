variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "Region, used to build the S3 gateway endpoint service name"
  type        = string
}

variable "vpc_id" {
  description = "Existing VPC. Nothing about the VPC itself is modified; resources are added inside it."
  type        = string
}

variable "nat_public_subnet_id" {
  description = "Existing PUBLIC subnet that hosts the NAT gateway. Must have a route to the internet gateway."
  type        = string
}

variable "availability_zone" {
  description = "AZ for the private subnet. Kept the same as the NAT gateway's AZ so Glue traffic never crosses an AZ boundary, which would add data transfer cost for no benefit."
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR for the new private subnet that Glue ENIs are placed in. Must not overlap the three existing default-VPC subnets, which occupy 172.31.0.0/20, 172.31.16.0/20 and 172.31.32.0/20."
  type        = string
  default     = "172.31.128.0/20"
}
