terraform {
  required_version = ">= 1.5.0"

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