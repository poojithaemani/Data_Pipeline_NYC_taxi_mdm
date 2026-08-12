"""Delta Lake time-travel and schema-evolution demonstration.

Satisfies the remaining training-plan deliverable without touching anything
the pipeline depends on. Everything this job reads is read-only, and
everything it writes lives under a dedicated demo/ prefix:

    demo/delta_demo_zones/   the demonstration Delta table
    demo/evidence/           a JSON record of what was proven

Production Silver, Gold, warehouse, master, Redshift, QuickSight and the MDM
database are never written to. The only production data touched is the Bronze
taxi zone CSV, which is read.

Why a real table rather than a toy
----------------------------------
The demonstration uses the project's own reference data - the 265 NYC taxi
zones - so the versions, the update and the evolved column are recognisable
against the rest of the platform rather than being abstract fixtures.

What is demonstrated, in order
------------------------------
    v0  initial write            265 zones, 4 columns
    v1  controlled change        one row updated in place
    v2  schema evolution         3 rows appended carrying a new column,
                                 written with mergeSchema

Then, without rewriting anything:

    * DESCRIBE HISTORY lists all three versions with their operations
    * version 0 is read back and still has the ORIGINAL 4-column schema and
      the ORIGINAL value of the row that v1 changed
    * version 1 is read back and shows the changed value but still the
      original schema
    * the current version carries the EVOLVED 5-column schema

The table is deleted and rebuilt at the start of every run so version numbers
are deterministic - a reader can always expect exactly 0, 1 and 2.
"""

import json
import sys
from datetime import datetime

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from delta.tables import DeltaTable
from pyspark.sql import SparkSession, functions as F

# The zone whose service_zone the controlled change rewrites. location_id 1
# (EWR / Newark Airport) is the same row the MDM pipeline has versioned via
# SCD Type 2, which makes the parallel between Delta versioning and SCD2
# versioning easy to point at.
DEMO_LOCATION_ID = 1
UPDATED_SERVICE_ZONE = "DEMO_UPDATED"

# Rows appended in v2. They carry a column the table does not yet have, which
# is what forces the schema to evolve.
EVOLVED_ROWS = [
    (900, "DEMO", "Demo Zone Alpha", "Demo", "airport"),
    (901, "DEMO", "Demo Zone Beta", "Demo", "residential"),
    (902, "DEMO", "Demo Zone Gamma", "Demo", "commercial"),
]
NEW_COLUMN = "zone_category"


def _split_s3_uri(uri):
    bucket, _, key = uri.replace("s3://", "", 1).partition("/")
    return bucket, key


def reset_demo_table(table_path, logger):
    """Delete any previous demo table so version numbers start at 0 again.

    Scoped to the demo table prefix only. Nothing outside demo/ is listed or
    deleted.
    """
    bucket, prefix = _split_s3_uri(table_path)
    prefix = prefix.rstrip("/") + "/"
    s3 = boto3.client("s3")

    deleted = 0
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        keys = [{"Key": o["Key"]} for o in page.get("Contents", [])]
        if keys:
            s3.delete_objects(Bucket=bucket, Delete={"Objects": keys})
            deleted += len(keys)
    logger.info(f"Reset demo table at {table_path}: removed {deleted} object(s).")
    return deleted


def build_seed_dataframe(spark, zones_csv_path, logger):
    """Read the Bronze taxi zone reference CSV. Read-only.

    Column names are resolved case-insensitively rather than hardcoded. The
    frozen golden_zone_etl.py supplies an explicit schema and therefore maps
    the CSV by position, which hides what the header actually says; this job
    reads the header, so it has to cope with either the TLC's original
    LocationID/Borough/Zone casing or the snake_case the file currently uses.
    """
    logger.info(f"Reading demo seed data from {zones_csv_path}")
    raw = spark.read.option("header", "true").csv(zones_csv_path)
    logger.info(f"Source header: {raw.columns}")

    available = {c.lower(): c for c in raw.columns}

    def pick(*candidates):
        for candidate in candidates:
            if candidate.lower() in available:
                return available[candidate.lower()]
        raise ValueError(
            f"None of {candidates} present in source columns {raw.columns}"
        )

    return raw.select(
        F.col(pick("location_id", "LocationID")).cast("int").alias("location_id"),
        F.col(pick("borough", "Borough")).alias("borough"),
        F.col(pick("zone", "Zone")).alias("zone"),
        F.col(pick("service_zone", "ServiceZone")).alias("service_zone"),
    ).orderBy("location_id")


def describe_history(spark, table_path):
    """DESCRIBE HISTORY, oldest version first."""
    history = (
        DeltaTable.forPath(spark, table_path)
        .history()
        .select("version", "timestamp", "operation", "operationMetrics")
        .orderBy("version")
        .collect()
    )
    return [
        {
            "version": int(row["version"]),
            "timestamp": row["timestamp"].isoformat() if row["timestamp"] else None,
            "operation": row["operation"],
            "operationMetrics": {k: v for k, v in (row["operationMetrics"] or {}).items()},
        }
        for row in history
    ]


def read_version(spark, table_path, version):
    """Time-travel read of a specific version."""
    return (
        spark.read.format("delta")
        .option("versionAsOf", version)
        .load(table_path)
    )


def snapshot(df, label):
    """Capture the facts that prove which version was read."""
    demo_row = (
        df.filter(F.col("location_id") == DEMO_LOCATION_ID)
        .select("service_zone")
        .collect()
    )
    return {
        "label": label,
        "row_count": df.count(),
        "columns": df.columns,
        "column_count": len(df.columns),
        f"has_{NEW_COLUMN}": NEW_COLUMN in df.columns,
        f"service_zone_of_location_{DEMO_LOCATION_ID}": (
            demo_row[0]["service_zone"] if demo_row else None
        ),
    }


def main():
    args = getResolvedOptions(
        sys.argv, ["JOB_NAME", "demo_path", "zones_csv_path"]
    )
    job_name = args["JOB_NAME"]

    # Also requested here in case this script is what first materialises the
    # session; Spark can only register extensions at creation time, so the
    # --conf job argument is the authoritative path and this is a fallback.
    spark = (
        SparkSession.builder
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .getOrCreate()
    )
    glue_context = GlueContext(spark.sparkContext)
    job = Job(glue_context)
    job.init(job_name, args)
    logger = glue_context.get_logger()

    demo_path = args["demo_path"].rstrip("/")
    table_path = f"{demo_path}/delta_demo_zones"
    evidence_key_path = f"{demo_path}/evidence/delta_demo_evidence.json"

    start_time = datetime.now()
    job_status = "FAILED"
    evidence = {}

    try:
        reset_demo_table(table_path, logger)

        # ---------------- v0: initial write ----------------
        seed_df = build_seed_dataframe(spark, args["zones_csv_path"], logger)
        (
            seed_df.write.format("delta")
            .mode("overwrite")
            .option("compression", "snappy")
            .save(table_path)
        )
        logger.info(f"v0 written: {seed_df.count()} rows, columns {seed_df.columns}")

        # ---------------- v1: controlled change ----------------
        # An in-place UPDATE, which Delta records as a new version rather than
        # mutating the previous one - that is what makes v0 still readable.
        delta_table = DeltaTable.forPath(spark, table_path)
        delta_table.update(
            condition=F.col("location_id") == DEMO_LOCATION_ID,
            set={"service_zone": F.lit(UPDATED_SERVICE_ZONE)},
        )
        logger.info(
            f"v1 written: location_id {DEMO_LOCATION_ID} service_zone "
            f"-> {UPDATED_SERVICE_ZONE}"
        )

        # ---------------- v2: schema evolution ----------------
        evolved_df = spark.createDataFrame(
            EVOLVED_ROWS,
            schema=f"location_id int, borough string, zone string, "
                   f"service_zone string, {NEW_COLUMN} string",
        )
        (
            evolved_df.write.format("delta")
            .mode("append")
            .option("mergeSchema", "true")
            .option("compression", "snappy")
            .save(table_path)
        )
        logger.info(f"v2 written: appended {len(EVOLVED_ROWS)} rows adding '{NEW_COLUMN}'")

        # ---------------- read back and prove ----------------
        history = describe_history(spark, table_path)
        v0 = snapshot(read_version(spark, table_path, 0), "version 0 - initial")
        v1 = snapshot(read_version(spark, table_path, 1), "version 1 - after update")
        current_df = spark.read.format("delta").load(table_path)
        current = snapshot(current_df, "current - after schema evolution")

        # Rows that predate the new column must read back as NULL for it,
        # which is what proves the column was added rather than backfilled.
        nulls_in_new_column = current_df.filter(F.col(NEW_COLUMN).isNull()).count()

        checks = {
            "history_has_three_versions": len(history) == 3,
            "v0_has_original_schema": not v0[f"has_{NEW_COLUMN}"],
            "v1_has_original_schema": not v1[f"has_{NEW_COLUMN}"],
            "current_has_evolved_schema": current[f"has_{NEW_COLUMN}"],
            "v0_retains_original_value": (
                v0[f"service_zone_of_location_{DEMO_LOCATION_ID}"] != UPDATED_SERVICE_ZONE
            ),
            "v1_shows_updated_value": (
                v1[f"service_zone_of_location_{DEMO_LOCATION_ID}"] == UPDATED_SERVICE_ZONE
            ),
            "row_count_grew_by_appended_rows": (
                current["row_count"] == v0["row_count"] + len(EVOLVED_ROWS)
            ),
            "pre_evolution_rows_null_in_new_column": (
                nulls_in_new_column == v0["row_count"]
            ),
        }

        evidence = {
            "job_name": job_name,
            "generated_at": start_time.isoformat(),
            "table_path": table_path,
            "history": history,
            "versions": {"v0": v0, "v1": v1, "current": current},
            "nulls_in_new_column": nulls_in_new_column,
            "checks": checks,
            "all_checks_passed": all(checks.values()),
        }

        bucket, key = _split_s3_uri(evidence_key_path)
        boto3.client("s3").put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(evidence, indent=2).encode("utf-8"),
            ContentType="application/json",
        )
        logger.info(f"Evidence written to {evidence_key_path}")

        if not evidence["all_checks_passed"]:
            failed = [k for k, v in checks.items() if not v]
            raise ValueError(f"Delta demonstration checks failed: {failed}")

        job_status = "COMPLETED"

    except Exception as exc:
        logger.error(f"A fatal error occurred in job {job_name}: {exc}")
        raise

    finally:
        end_time = datetime.now()
        logger.info(
            "Final job summary: "
            + json.dumps(
                {
                    "job_name": job_name,
                    "status": job_status,
                    "start_time": start_time.isoformat(),
                    "end_time": end_time.isoformat(),
                    "duration_seconds": (end_time - start_time).total_seconds(),
                    "execution_summary": evidence.get("checks", {"error": "no evidence"}),
                },
                indent=2,
            )
        )
        job.commit()


if __name__ == "__main__":
    main()
