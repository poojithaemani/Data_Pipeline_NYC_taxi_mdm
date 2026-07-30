# Athena Workgroup for queries and result configuration

resource "aws_athena_workgroup" "this" {
  name = var.athena_workgroup_name != "" ? var.athena_workgroup_name : "${var.project_name}-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.bucket_name}/${var.athena_results_prefix}"
      encryption_configuration {
        encryption_option = var.enable_kms_for_athena ? "SSE_KMS" : "SSE_S3"
        kms_key_arn       = var.enable_kms_for_athena ? var.kms_key_id : null
      }
    }
  }

  description = "Athena workgroup for ${var.project_name}"
}

