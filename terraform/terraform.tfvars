bucket_name = "emani-nyc-taxi-bucket"

project_name = "nyc-taxi-mdm-platform"

environment = "dev"

aws_region = "us-east-2"

log_retention_days = 30

vpc_id = "vpc-037ccb54d062c2fda"

subnet_ids = [
  "subnet-071352e9d616e1770",
  "subnet-0ade670b11a3e3f2c"
]

# allowed_cidr_blocks = [
#   "2601:600:9001:8650:4cad:af9a:df17:95a8"
# ]

allowed_ipv4_cidr_blocks = [
  "10.0.0.60"
]

database_name = "taxi_mdm"

master_username = "postgres"

master_password = "Poojitha123"

allocated_storage = 20

instance_class = "db.t3.micro"