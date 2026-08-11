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

  # Security phase: was SSE-S3 (AES256) with an AWS owned key. Default
  # encryption applies to NEW objects only, so every existing object stays
  # readable exactly as before and no re-encryption backfill is required.
  #
  # bucket_key_enabled matters more with a CMK than it did with SSE-S3: it
  # collapses per-object KMS calls into a bucket-level data key, which keeps
  # KMS request cost flat across millions of Parquet part files.
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
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