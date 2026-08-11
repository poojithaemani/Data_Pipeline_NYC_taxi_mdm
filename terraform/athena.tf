# Athena Workgroup for queries and result configuration

resource "aws_athena_workgroup" "this" {
  name = var.athena_workgroup_name != "" ? var.athena_workgroup_name : "${var.project_name}-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.bucket_name}/${var.athena_results_prefix}"
      # Security phase: the CMK now backs Athena result encryption. The
      # enable_kms_for_athena / kms_key_id hooks already existed here; they
      # are wired to the project key rather than left inert.
      encryption_configuration {
        encryption_option = var.create_orchestration ? "SSE_KMS" : "SSE_S3"
        kms_key_arn       = var.create_orchestration ? module.kms[0].key_arn : null
      }
    }
  }

  description = "Athena workgroup for ${var.project_name}"
}

