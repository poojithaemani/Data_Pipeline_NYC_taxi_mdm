# Glue Catalog Databases for Phase 2 - Bronze, Silver, Gold, Master

resource "aws_glue_catalog_database" "bronze" {
  name        = var.bronze_db_name
  description = "Glue database for Bronze zone"
}

resource "aws_glue_catalog_database" "silver" {
  name        = var.silver_db_name
  description = "Glue database for Silver zone"
}

resource "aws_glue_catalog_database" "gold" {
  name        = var.gold_db_name
  description = "Glue database for Gold zone"
}

resource "aws_glue_catalog_database" "master" {
  name        = var.master_db_name
  description = "Glue database for Master data (MDM)"
}
