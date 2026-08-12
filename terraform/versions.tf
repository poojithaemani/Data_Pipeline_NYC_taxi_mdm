terraform {
  # use_lockfile needs 1.10+; S3 conditional writes replace the DynamoDB lock
  # table the older pattern required.
  required_version = ">= 1.10.0"

  # Remote state. Values are hardcoded rather than passed as -backend-config
  # because a backend block cannot interpolate variables, and none of these
  # are secrets - the bucket is private and the state inside it is what
  # matters. The bucket itself is managed in backend.tf, which is why the
  # first apply ran against local state.
  backend "s3" {
    bucket       = "nyc-taxi-mdm-platform-tfstate-749185461065"
    key          = "nyc-taxi-mdm/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # Generates the rotated RDS master password at apply time so the value
    # never has to exist in tfvars or any other file.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}