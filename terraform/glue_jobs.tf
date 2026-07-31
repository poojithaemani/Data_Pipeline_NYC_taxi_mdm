################################################################################
# Glue Job Scripts - Upload to S3
#
# Manages the Glue ETL Python scripts as S3 objects. This ensures that the
# correct version of the script is deployed with the infrastructure.
################################################################################

resource "aws_s3_object" "silver_etl_script" {
  bucket = var.bucket_name
  key    = "glue/scripts/yellow_taxi_silver_etl.py"
  source = "${path.module}/../pipeline/glue/jobs/yellow_taxi_silver_etl.py"
  etag   = filemd5("${path.module}/../pipeline/glue/jobs/yellow_taxi_silver_etl.py")

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_object" "gold_etl_script" {
  bucket = var.bucket_name
  key    = "glue/scripts/yellow_taxi_gold_etl.py"
  source = "${path.module}/../pipeline/glue/jobs/yellow_taxi_gold_etl.py"
  etag   = filemd5("${path.module}/../pipeline/glue/jobs/yellow_taxi_gold_etl.py")

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

################################################################################
# AWS Glue Jobs
#
# Defines the Bronze-to-Silver and Silver-to-Gold ETL jobs.
################################################################################

resource "aws_glue_job" "silver_etl" {
  name         = "${var.project_name}-yellow-taxi-silver-etl"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  number_of_workers = 2

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_object.silver_etl_script.bucket}/${aws_s3_object.silver_etl_script.key}"
  }

  default_arguments = {
    "--job-language"                                      = "python"
    "--job-bookmark-option"                               = "job-bookmark-disable"
    "--enable-metrics"                                    = ""
    "--spark-sql-extensions"                              = "io.delta.sql.DeltaSparkSessionExtension"
    "--spark-sql-catalog-spark_catalog"                   = "org.apache.spark.sql.delta.catalog.DeltaCatalog"
    "--additional-python-modules"                         = "pyarrow>=15.0.0"
    "--bronze_path"                                       = "s3://${var.bucket_name}/bronze/transactions/yellow_taxi/"
    "--silver_path"                                       = "s3://${var.bucket_name}/silver/yellow_taxi/"
  }

  tags = {
    Name        = "${var.project_name}-yellow-taxi-silver-etl"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_glue_job" "gold_etl" {
  name         = "${var.project_name}-yellow-taxi-gold-etl"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  number_of_workers = 2

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_object.gold_etl_script.bucket}/${aws_s3_object.gold_etl_script.key}"
  }

  default_arguments = {
    "--job-language"                                      = "python"
    "--job-bookmark-option"                               = "job-bookmark-disable"
    "--enable-metrics"                                    = ""
    "--spark-sql-extensions"                              = "io.delta.sql.DeltaSparkSessionExtension"
    "--spark-sql-catalog-spark_catalog"                   = "org.apache.spark.sql.delta.catalog.DeltaCatalog"
    "--additional-python-modules"                         = "pyarrow>=15.0.0"
    "--silver_path"                                       = "s3://${var.bucket_name}/silver/yellow_taxi/"
    "--gold_path"                                         = "s3://${var.bucket_name}/gold/yellow_taxi/"
  }

  tags = {
    Name        = "${var.project_name}-yellow-taxi-gold-etl"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
