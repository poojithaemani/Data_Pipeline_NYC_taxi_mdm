resource "aws_s3_bucket" "data_lake" {
  bucket = var.bucket_name

  tags = {
    Name        = var.bucket_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

locals {
  folders = [
    "bronze/",
    "silver/",
    "gold/",
    "quality/",
    "logs/",
    "metadata/",
    "checkpoints/"
  ]
}

resource "aws_s3_object" "folders" {
  for_each = toset(local.folders)

  bucket  = aws_s3_bucket.data_lake.id
  key     = each.value
  content = ""
}