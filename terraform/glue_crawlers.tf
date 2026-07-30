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
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_glue_crawler" "silver" {
  name          = var.silver_crawler_name
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.silver.name

  s3_target {
    path = "s3://${var.bucket_name}/silver/"
  }

  table_prefix = "silver_"

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_glue_crawler" "gold" {
  name          = var.gold_crawler_name
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.gold.name

  s3_target {
    path = "s3://${var.bucket_name}/gold/"
  }

  table_prefix = "gold_"

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

