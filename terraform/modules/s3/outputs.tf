output "bucket_id" {
  description = "S3 Bucket ID"
  value       = aws_s3_bucket.data_lake.id
}

output "bucket_name" {
  description = "S3 Bucket Name"
  value       = aws_s3_bucket.data_lake.bucket
}

output "bucket_arn" {
  description = "S3 Bucket ARN"
  value       = aws_s3_bucket.data_lake.arn
}

output "bucket_domain_name" {
  description = "S3 Bucket Domain Name"
  value       = aws_s3_bucket.data_lake.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional Domain Name"
  value       = aws_s3_bucket.data_lake.bucket_regional_domain_name
}