# Glue Crawlers for Bronze, Silver, Gold

resource "aws_glue_crawler" "bronze" {
  name          = var.bronze_crawler_name
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.bronze.name

  s3_target {
    path = "s3://${var.bucket_name}/bronze/"
  }

  table_prefix = "bronze_"

  schema_change_policy {
    delete_behavior = "DELETE_FROM_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_glue_crawler" "silver" {
  name          = var.silver_crawler_name
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.silver.name
  description   = "Native Delta Lake crawler for the Silver layer."

  # Switched from s3_target to delta_target to correctly catalog the Delta Lake table.
  delta_target {
    delta_tables              = ["s3://${var.bucket_name}/${var.silver_delta_table_path}/"]
    create_native_delta_table = true # Required for Athena v3 native Delta queries
    write_manifest            = false
  }

  schema_change_policy {
    delete_behavior = "DELETE_FROM_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
  }

}

resource "aws_glue_crawler" "gold" {
  name          = var.gold_crawler_name
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.gold.name
  description   = "Native Delta Lake crawler for the Gold layer."

  # Switched to delta_target to correctly catalog the single Gold Delta Lake table.
  # Each summary table is a separate Delta table and must be listed individually.
  delta_target {
    delta_tables = [
      "s3://${var.bucket_name}/${var.gold_delta_table_path}/daily_summary/",
      "s3://${var.bucket_name}/${var.gold_delta_table_path}/vendor_summary/",
      "s3://${var.bucket_name}/${var.gold_delta_table_path}/borough_summary/",
      "s3://${var.bucket_name}/${var.gold_delta_table_path}/payment_summary/",
      "s3://${var.bucket_name}/${var.gold_delta_table_path}/hourly_summary/"
    ]
    create_native_delta_table = true # Required for Athena v3 native Delta queries
    write_manifest            = false
  }

  schema_change_policy {
    delete_behavior = "DELETE_FROM_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
  }

}
