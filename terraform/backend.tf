############################################
# Remote Terraform state
#
# Why this exists
# ---------------
# State lived on the operator's machine and was gitignored, so a CI runner had
# nothing to diff against - a plan there would have reported all 111 managed
# resources as "to create". That made a real pull-request plan impossible.
#
# Bootstrap order (this is self-referential by design)
# ----------------------------------------------------
# This bucket is created by the same configuration whose state it will hold:
#
#   1. apply with local state  -> the bucket exists
#   2. add the backend block   -> terraform init -migrate-state
#   3. plan                    -> must report no changes
#
# prevent_destroy is what stops step 3 from ever becoming "terraform destroy
# deletes the bucket holding its own state".
#
# Locking uses S3 conditional writes (use_lockfile), available from Terraform
# 1.10. No DynamoDB table is needed, which is one less resource to own.
############################################

resource "aws_s3_bucket" "tfstate" {
  bucket = var.tfstate_bucket_name

  # Deleting this bucket would destroy the record of every other resource in
  # the platform. Removing this block should be a deliberate, reviewed act.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = var.tfstate_bucket_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "terraform-remote-state"
  }
}

# Non-negotiable for a state bucket: versioning is the only way back from a
# corrupted or truncated state write.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 rather than the project CMK, deliberately. State is the recovery path
# for everything else; making it readable only through a customer managed key
# means a disabled or pending-deletion key would lock the operator out of the
# very file needed to fix it. The bucket is private and versioned, and state
# is encrypted at rest either way.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Old state versions are kept long enough to recover from a bad apply, then
# expired so the bucket does not grow without bound.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
