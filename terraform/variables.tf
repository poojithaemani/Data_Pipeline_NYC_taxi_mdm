variable "aws_region" {
  description = "AWS Region"
  type        = string
}
variable "bucket_name" {
  type = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to the database. WARNING: The default value '0.0.0.0/0' is insecure and should not be used in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "database_name" {
  type = string
}

variable "master_username" {
  type      = string
  sensitive = true
}

variable "master_password" {
  type      = string
  sensitive = true
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allowed_ipv4_cidr_blocks" {
  description = "Allowed IPv4 CIDR blocks"
  type        = list(string)
  default     = []
}
