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
  # source_hash, not etag: the bucket defaults to SSE-KMS, and S3 does not
  # return the MD5 as the ETag for KMS-encrypted objects, so an etag/filemd5
  # comparison can never converge once the object is re-uploaded.
  source_hash = filemd5("${path.module}/../pipeline/glue/jobs/yellow_taxi_silver_etl.py")

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
  # source_hash, not etag: the bucket defaults to SSE-KMS, and S3 does not
  # return the MD5 as the ETag for KMS-encrypted objects, so an etag/filemd5
  # comparison can never converge once the object is re-uploaded.
  source_hash = filemd5("${path.module}/../pipeline/glue/jobs/yellow_taxi_gold_etl.py")

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_object" "golden_zone_etl_script" {
  bucket = var.bucket_name
  key    = "glue/scripts/golden_zone_etl.py"
  source = "${path.module}/../pipeline/glue/jobs/golden_zone_etl.py"
  # source_hash, not etag: the bucket defaults to SSE-KMS, and S3 does not
  # return the MD5 as the ETag for KMS-encrypted objects, so an etag/filemd5
  # comparison can never converge once the object is re-uploaded.
  source_hash = filemd5("${path.module}/../pipeline/glue/jobs/golden_zone_etl.py")

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_object" "warehouse_export_script" {
  bucket = var.bucket_name
  key    = "glue/scripts/warehouse_export_etl.py"
  source = "${path.module}/../pipeline/glue/jobs/warehouse_export_etl.py"
  # source_hash, not etag: the bucket defaults to SSE-KMS, and S3 does not
  # return the MD5 as the ETag for KMS-encrypted objects, so an etag/filemd5
  # comparison can never converge once the object is re-uploaded.
  source_hash = filemd5("${path.module}/../pipeline/glue/jobs/warehouse_export_etl.py")

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_object" "glue_temp_dir" {
  bucket  = var.bucket_name
  key     = "glue/temp/"
  content = "" # Empty content for a folder placeholder

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Description = "Placeholder for Glue temporary directory"
  }
}

################################################################################
# AWS Glue Jobs
#
# Defines the Bronze-to-Silver and Silver-to-Gold ETL jobs.
################################################################################

locals {
  # Common default arguments for all Glue ETL jobs
  common_glue_job_args = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-glue-datacatalog"          = "true"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--datalake-formats"                 = "delta"
    "--TempDir"                          = "s3://${var.bucket_name}/glue/temp/"
    "--spark-sql-extensions"             = "io.delta.sql.DeltaSparkSessionExtension"
    "--spark-sql-catalog-spark_catalog"  = "org.apache.spark.sql.delta.catalog.DeltaCatalog"
    "--additional-python-modules"        = "pyarrow>=15.0.0"
  }
}

resource "aws_glue_job" "silver_etl" {
  name              = "${var.project_name}-yellow-taxi-silver-etl"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "4.0"
  worker_type       = var.glue_job_worker_type
  number_of_workers = var.glue_job_number_of_workers

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_object.silver_etl_script.bucket}/${aws_s3_object.silver_etl_script.key}"
  }

  default_arguments = merge(
    local.common_glue_job_args,
    {
      "--bronze_path" = "s3://${var.bucket_name}/${var.bronze_transactions_path}"
      "--silver_path" = "s3://${var.bucket_name}/${var.silver_delta_table_path}/"
    }
  )

  tags = {
    Name        = "${var.project_name}-yellow-taxi-silver-etl"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_glue_job" "golden_zone_etl" {
  # Runs inside the VPC so it can reach the now-private RDS instance.
  connections = var.create_orchestration ? [module.network[0].glue_connection_name] : []

  name              = "${var.project_name}-golden-zone-etl"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "4.0"
  worker_type       = var.glue_job_worker_type
  number_of_workers = var.glue_job_number_of_workers

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_object.golden_zone_etl_script.bucket}/${aws_s3_object.golden_zone_etl_script.key}"
  }

  default_arguments = merge(
    local.common_glue_job_args,
    {
      # This job needs the pg8000 library to connect to PostgreSQL
      "--additional-python-modules" = "pyarrow>=15.0.0,pg8000"
      # Must match the key written by the ingestion pipeline
      # (pipeline/ingestion/orchestrator.py -> bronze/reference/<source>/<source>.csv)
      "--input_path" = "s3://${var.bucket_name}/${var.bronze_reference_path}taxi_zones/taxi_zones.csv"

      # Following the existing pattern of passing DB credentials as arguments.
      # This will be enhanced later with Secrets Manager.
      "--DB_HOST" = var.create_rds ? module.rds[0].db_address : ""
      "--DB_PORT" = var.create_rds ? module.rds[0].db_port : ""
      "--DB_NAME" = var.database_name

      # Security phase: --DB_USER and --DB_PASSWORD are gone. A job argument
      # is readable by anyone holding glue:GetJob and persists in the job
      # definition, so the credential is fetched from Secrets Manager at
      # runtime instead. Only the ARN travels as an argument.
      "--SECRET_ARN" = var.create_orchestration ? module.secrets[0].rds_master_secret_arn : ""
    }
  )

  tags = {
    Name        = "${var.project_name}-golden-zone-etl"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_glue_job" "gold_etl" {
  name              = "${var.project_name}-yellow-taxi-gold-etl"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "4.0"
  worker_type       = var.glue_job_worker_type
  number_of_workers = var.glue_job_number_of_workers

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_object.gold_etl_script.bucket}/${aws_s3_object.gold_etl_script.key}"
  }

  default_arguments = merge(
    local.common_glue_job_args,
    {
      "--silver_path" = "s3://${var.bucket_name}/${var.silver_delta_table_path}/"
      "--gold_path"   = "s3://${var.bucket_name}/${var.gold_delta_table_path}/"
    }
  )

  tags = {
    Name        = "${var.project_name}-yellow-taxi-gold-etl"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

################################################################################
# Warehouse Export ETL
#
# Builds the Redshift-ready star schema snapshot as plain Parquet under the
# warehouse/ prefix. Redshift COPY cannot read Delta Lake, so this export is
# required regardless; producing a separate dataset leaves the Silver and Gold
# Delta tables and their jobs completely untouched.
#
# Reads Silver (S3) and the mastered zone records (RDS), so it needs the same
# DB_* arguments as the golden zone job.
################################################################################

resource "aws_glue_job" "warehouse_export_etl" {
  # Runs inside the VPC so it can reach the now-private RDS instance.
  connections = var.create_orchestration ? [module.network[0].glue_connection_name] : []

  name              = "${var.project_name}-warehouse-export-etl"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "4.0"
  worker_type       = var.glue_job_worker_type
  number_of_workers = var.glue_job_number_of_workers

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_object.warehouse_export_script.bucket}/${aws_s3_object.warehouse_export_script.key}"
  }

  default_arguments = merge(
    local.common_glue_job_args,
    {
      # pg8000 is needed to read dim_zone from PostgreSQL, as in the golden zone job.
      "--additional-python-modules" = "pyarrow>=15.0.0,pg8000"

      "--silver_path"    = "s3://${var.bucket_name}/${var.silver_delta_table_path}/"
      "--warehouse_path" = "s3://${var.bucket_name}/${var.warehouse_path}"

      # Same credential-passing pattern as the golden zone job.
      "--DB_HOST" = var.create_rds ? module.rds[0].db_address : ""
      "--DB_PORT" = var.create_rds ? module.rds[0].db_port : ""
      "--DB_NAME" = var.database_name

      # Security phase: --DB_USER and --DB_PASSWORD are gone. A job argument
      # is readable by anyone holding glue:GetJob and persists in the job
      # definition, so the credential is fetched from Secrets Manager at
      # runtime instead. Only the ARN travels as an argument.
      "--SECRET_ARN" = var.create_orchestration ? module.secrets[0].rds_master_secret_arn : ""
    }
  )

  tags = {
    Name        = "${var.project_name}-warehouse-export-etl"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

################################################################################
# Operational tracking - sync_pipeline_runs
#
# The security phase made RDS private, so the sync script can no longer run
# from a workstation. It runs here instead: a Python Shell job on the same VPC
# connection, IAM role and secret the ETL jobs already use.
#
# Two objects are uploaded - the wrapper, which is the job's entry point, and
# the frozen scripts/sync_pipeline_runs.py itself, which the wrapper fetches
# and executes unmodified so the sync logic stays exactly as frozen.
################################################################################

resource "aws_s3_object" "sync_pipeline_runs_wrapper" {
  bucket = var.bucket_name
  key    = "glue/scripts/sync_pipeline_runs_job.py"
  source = "${path.module}/../pipeline/glue/jobs/sync_pipeline_runs_job.py"
  # source_hash, not etag: the bucket now defaults to SSE-KMS, and S3 does
  # not return the MD5 as the ETag for KMS-encrypted objects, so an
  # etag/filemd5 comparison can never converge.
  source_hash = filemd5("${path.module}/../pipeline/glue/jobs/sync_pipeline_runs_job.py")

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_object" "sync_pipeline_runs_script" {
  bucket = var.bucket_name
  key    = "glue/scripts/sync_pipeline_runs.py"
  source = "${path.module}/../scripts/sync_pipeline_runs.py"
  # source_hash, not etag: the bucket now defaults to SSE-KMS, and S3 does
  # not return the MD5 as the ETag for KMS-encrypted objects, so an
  # etag/filemd5 comparison can never converge.
  source_hash = filemd5("${path.module}/../scripts/sync_pipeline_runs.py")

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_glue_job" "sync_pipeline_runs" {
  # Runs inside the VPC so it can reach the private RDS instance.
  connections = var.create_orchestration ? [module.network[0].glue_connection_name] : []

  name     = "${var.project_name}-sync-pipeline-runs"
  role_arn = aws_iam_role.glue_role.arn

  # Python Shell, not Spark: this reads a few hundred Glue job runs and writes
  # at most a handful of rows. A Spark cluster would be pure overhead.
  glue_version = "3.0"
  max_capacity = 1.0

  command {
    name            = "pythonshell"
    python_version  = "3.9"
    script_location = "s3://${aws_s3_object.sync_pipeline_runs_wrapper.bucket}/${aws_s3_object.sync_pipeline_runs_wrapper.key}"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                          = "s3://${var.bucket_name}/glue/temp/"
    "--additional-python-modules"        = "psycopg2-binary"

    "--SCRIPT_S3_URI" = "s3://${aws_s3_object.sync_pipeline_runs_script.bucket}/${aws_s3_object.sync_pipeline_runs_script.key}"
    "--SECRET_ARN"    = var.create_orchestration ? module.secrets[0].rds_master_secret_arn : ""
    "--DB_HOST"       = var.create_rds ? module.rds[0].db_address : ""
    "--DB_PORT"       = var.create_rds ? tostring(module.rds[0].db_port) : ""
    "--DB_NAME"       = var.database_name
  }

  tags = {
    Name        = "${var.project_name}-sync-pipeline-runs"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
