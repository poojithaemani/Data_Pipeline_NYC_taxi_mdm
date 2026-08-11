"""
Warehouse export ETL: builds the Redshift-ready star schema snapshot.

Reads the frozen Silver Delta table and the mastered zone records in RDS, and
writes four plain Parquet datasets that Redshift COPY can load directly.

Why a separate job
------------------
Redshift COPY cannot read Delta Lake, so an export step is required regardless.
Producing a new dataset under warehouse/ keeps the frozen Silver and Gold ETL
jobs, and every Delta table they own, completely untouched.

Grain and fidelity
------------------
fact_trips is at trip grain and is a lossless projection of Silver: no filter,
no deduplication, no enrichment. The row count must equal Silver exactly or the
reconciliation against Gold is meaningless. Rows that look wrong (for example
the 321 trips with a negative total_amount that Silver never validated) are
carried through deliberately rather than silently dropped.

No surrogate trip key
---------------------
Silver has no stable natural trip identifier - the strongest available composite
still collides on one pair of rows - and nothing downstream needs one. A Redshift
IDENTITY column would be worse than nothing: values are assigned
non-deterministically across slices, so a reload would renumber every trip and
the warehouse would stop being reproducible.

Dimension sourcing
------------------
dim_zone is driven from zone_matches, the validated MDM matching output. That
excludes the location_id = 99999 test fixture structurally rather than by a
magic-number filter - which matters, because the fixture's version 2 is
is_current = TRUE and a naive `WHERE is_current` returns 266 rows, not 265.

The current golden record is resolved by business key, through
zone_matches.source_zone_id -> taxi_zones.location_id -> golden_zones.location_id
WHERE is_current. It is deliberately NOT resolved through
zone_matches.golden_zone_row_id: that column is a pointer to one specific SCD
Type 2 version row, and nothing repoints it when the golden zone job supersedes
that version. Joining on it silently drops every zone that has ever been
updated - which is exactly what happened when location_id 1 (EWR) gained a
version 3 and this job's guard correctly refused to publish a 264-row
dimension. Joining by location_id always resolves to whichever version is
current, so the export survives any number of future SCD2 updates while
zone_matches keeps its historical pointer untouched.
"""

import json
import ssl
import sys
from datetime import datetime

import pg8000.dbapi
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import (
    DecimalType,
    IntegerType,
    LongType,
    ShortType,
    StringType,
    StructField,
    StructType,
)

# Full TLC payment code set. Loaded in its entirety rather than only the codes
# present in the current data, so a later month containing code 0 or 6 cannot
# produce orphan facts.
PAYMENT_TYPES = [
    (0, "Flex Fare trip"),
    (1, "Credit card"),
    (2, "Cash"),
    (3, "No charge"),
    (4, "Dispute"),
    (5, "Unknown"),
    (6, "Voided trip"),
]

# Business-key range of the NYC Taxi Zone lookup. Used as a defensive guard
# alongside the zone_matches join.
MIN_LOCATION_ID = 1
MAX_LOCATION_ID = 265

# Targets roughly 12 output files for fact_trips so COPY parallelises across
# slices. fact_trips is deliberately NOT partitioned: COPY ignores Hive-style
# partitioning and Spark strips partition columns out of the data files, which
# would load date_key as NULL for every row.
FACT_OUTPUT_FILES = 12

DIM_ZONE_QUERY = """
    SELECT g.location_id,
           g.borough,
           g.zone,
           g.service_zone,
           g.golden_zone_row_id,
           g.version
    FROM zone_matches zm
    JOIN taxi_zones t
      ON t.location_id = zm.source_zone_id
    JOIN golden_zones g
      ON g.location_id = t.location_id
    WHERE g.is_current
      AND g.location_id BETWEEN %s AND %s
    ORDER BY g.location_id
"""

DIM_ZONE_SCHEMA = StructType([
    StructField("location_id", ShortType(), False),
    StructField("borough", StringType(), False),
    StructField("zone", StringType(), False),
    StructField("service_zone", StringType(), False),
    StructField("golden_zone_row_id", LongType(), False),
    StructField("version", ShortType(), False),
])


def _db_credentials(secret_arn, logger):
    """Fetch the database username and password from Secrets Manager.

    Security phase: the password used to arrive as a --DB_PASSWORD job
    argument, which any principal holding glue:GetJob could read and which
    persisted in the job definition. Only the secret ARN travels as an
    argument now; the credential is resolved at runtime and never written
    anywhere.
    """
    import boto3

    logger.info("Fetching database credentials from Secrets Manager.")
    client = boto3.client("secretsmanager")
    secret = json.loads(client.get_secret_value(SecretId=secret_arn)["SecretString"])
    return secret["username"], secret["password"]


def _ssl_context():
    """TLS context for pg8000.

    The instance sets rds.force_ssl = 1, and pg8000 does not negotiate TLS
    unless it is handed a context. Certificate verification is left off
    because the RDS CA bundle is not staged in the Glue container; the
    connection is still encrypted in transit. Pinning the RDS CA is a
    tracked follow-up.
    """
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def get_db_connection(job_args, logger):
    """Open a PostgreSQL connection using the job's DB_* arguments."""
    required_keys = {"DB_HOST", "DB_PORT", "DB_NAME", "SECRET_ARN"}
    missing = required_keys - set(job_args)
    if missing:
        raise ValueError(f"Missing required DB arguments: {sorted(missing)}")

    username, password = _db_credentials(job_args["SECRET_ARN"], logger)

    logger.info(f"Connecting to database host: {job_args['DB_HOST']}")
    conn = pg8000.dbapi.connect(
        host=job_args["DB_HOST"],
        port=int(job_args["DB_PORT"]),
        database=job_args["DB_NAME"],
        user=username,
        password=password,
        ssl_context=_ssl_context(),
    )
    logger.info("Database connection successful.")
    return conn


def build_fact_trips(spark, silver_path, logger):
    """Project the Silver Delta table onto the fact_trips column set.

    This is a pure SELECT plus casts. Nothing is filtered or deduplicated, so
    the output row count is identical to Silver by construction.
    """
    logger.info(f"Reading Silver Delta table from: {silver_path}")
    silver_df = spark.read.format("delta").load(silver_path)

    money = DecimalType(10, 2)

    fact_df = silver_df.select(
        F.col("VendorID").cast(ShortType()).alias("vendorid"),
        F.col("tpep_pickup_datetime").alias("pickup_datetime"),
        F.col("tpep_dropoff_datetime").alias("dropoff_datetime"),
        F.date_format(F.col("tpep_pickup_datetime"), "yyyyMMdd")
         .cast(IntegerType()).alias("date_key"),
        F.col("PULocationID").cast(ShortType()).alias("pickup_location_id"),
        F.col("DOLocationID").cast(ShortType()).alias("dropoff_location_id"),
        F.col("payment_type").cast(ShortType()).alias("payment_type"),
        F.col("passenger_count").cast(ShortType()).alias("passenger_count"),
        F.col("trip_distance").cast(money).alias("trip_distance"),
        F.col("fare_amount").cast(money).alias("fare_amount"),
        F.col("tip_amount").cast(money).alias("tip_amount"),
        F.col("total_amount").cast(money).alias("total_amount"),
    )

    return fact_df


def build_dim_zone(spark, job_args, logger):
    """Read the 265 current mastered zones via the zone_matches join."""
    conn = None
    try:
        conn = get_db_connection(job_args, logger)
        cursor = conn.cursor()
        cursor.execute(DIM_ZONE_QUERY, (MIN_LOCATION_ID, MAX_LOCATION_ID))
        rows = cursor.fetchall()
        cursor.close()
    finally:
        if conn:
            conn.close()
            logger.info("Database connection closed.")

    # 265 rows: small enough to materialise on the driver.
    records = [
        (int(r[0]), r[1], r[2], r[3], int(r[4]), int(r[5]))
        for r in rows
    ]
    logger.info(f"Read {len(records)} current zone records from the MDM database.")

    return spark.createDataFrame(records, schema=DIM_ZONE_SCHEMA)


def build_dim_date(spark, fact_df, logger):
    """Generate a gap-free calendar spanning the fact's own pickup date range.

    Built from min/max rather than from the distinct dates present, so a future
    day with no trips still gets a dimension row instead of silently vanishing
    from every time series.
    """
    bounds = fact_df.select(
        F.min(F.to_date("pickup_datetime")).alias("min_date"),
        F.max(F.to_date("pickup_datetime")).alias("max_date"),
    ).collect()[0]

    min_date, max_date = bounds["min_date"], bounds["max_date"]
    logger.info(f"Generating dim_date calendar from {min_date} to {max_date}.")

    calendar_df = spark.sql(
        f"SELECT explode(sequence("
        f"  to_date('{min_date}'), to_date('{max_date}'), interval 1 day"
        f")) AS full_date"
    )

    # dayofweek() returns 1 = Sunday through 7 = Saturday.
    return calendar_df.select(
        F.date_format("full_date", "yyyyMMdd").cast(IntegerType()).alias("date_key"),
        F.col("full_date"),
        F.year("full_date").cast(ShortType()).alias("year"),
        F.month("full_date").cast(ShortType()).alias("month"),
        F.dayofmonth("full_date").cast(ShortType()).alias("day"),
        F.dayofweek("full_date").cast(ShortType()).alias("day_of_week"),
        F.date_format("full_date", "EEEE").alias("day_name"),
        F.dayofweek("full_date").isin(1, 7).alias("is_weekend"),
    ).orderBy("date_key")


def build_dim_payment(spark):
    """Static TLC payment-code dimension."""
    schema = StructType([
        StructField("payment_type", ShortType(), False),
        StructField("payment_description", StringType(), False),
    ])
    return spark.createDataFrame(PAYMENT_TYPES, schema=schema)


def write_parquet(df, output_path, logger, num_files=None):
    """Write a Snappy Parquet snapshot, overwriting any previous one."""
    logger.info(f"Writing Parquet to: {output_path}")
    writer = df.repartition(num_files) if num_files else df.coalesce(1)
    (
        writer.write.format("parquet")
        .mode("overwrite")
        .option("compression", "snappy")
        .save(output_path)
    )
    logger.info(f"Successfully wrote: {output_path}")


def main():
    job_args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "silver_path",
            "warehouse_path",
            "DB_HOST",
            "DB_PORT",
            "DB_NAME",
            "SECRET_ARN",
        ],
    )
    job_name = job_args["JOB_NAME"]

    spark = SparkSession.builder.getOrCreate()
    # Redshift COPY reads int64 micros timestamps; set explicitly rather than
    # relying on the Spark default so the snapshot format is deterministic.
    spark.conf.set("spark.sql.parquet.outputTimestampType", "TIMESTAMP_MICROS")

    glue_context = GlueContext(spark.sparkContext)
    job = Job(glue_context)
    job.init(job_name, job_args)
    logger = glue_context.get_logger()

    start_time = datetime.now()
    job_status = "FAILED"
    execution_summary = {}
    warehouse_path = job_args["warehouse_path"].rstrip("/")

    logger.info(f"Starting Glue job: {job_name}")

    try:
        fact_df = build_fact_trips(spark, job_args["silver_path"], logger)
        # Cached: the frame is counted, scanned for the date bounds, and written.
        fact_df.cache()
        fact_rows = fact_df.count()
        logger.info(f"fact_trips rows: {fact_rows}")

        dim_zone_df = build_dim_zone(spark, job_args, logger)
        dim_date_df = build_dim_date(spark, fact_df, logger)
        dim_payment_df = build_dim_payment(spark)

        dim_zone_rows = dim_zone_df.count()
        dim_date_rows = dim_date_df.count()
        dim_payment_rows = dim_payment_df.count()

        # Fail before writing rather than publishing a bad snapshot.
        if dim_zone_rows != 265:
            raise ValueError(
                f"dim_zone must contain exactly 265 rows, got {dim_zone_rows}"
            )
        if dim_payment_rows != len(PAYMENT_TYPES):
            raise ValueError(
                f"dim_payment must contain {len(PAYMENT_TYPES)} rows, got {dim_payment_rows}"
            )

        write_parquet(dim_zone_df, f"{warehouse_path}/dim_zone", logger)
        write_parquet(dim_date_df, f"{warehouse_path}/dim_date", logger)
        write_parquet(dim_payment_df, f"{warehouse_path}/dim_payment", logger)
        write_parquet(
            fact_df, f"{warehouse_path}/fact_trips", logger, num_files=FACT_OUTPUT_FILES
        )

        execution_summary = {
            # The warehouse snapshot is a full overwrite, so every fact row is
            # written on every run. "inserted" is reported so the existing
            # scripts/sync_pipeline_runs.py records a meaningful
            # records_processed value without needing to change.
            "inserted": fact_rows,
            "updated": 0,
            "no_change": 0,
            "errors": 0,
            "fact_trips_rows": fact_rows,
            "dim_zone_rows": dim_zone_rows,
            "dim_date_rows": dim_date_rows,
            "dim_payment_rows": dim_payment_rows,
            "fact_output_files": FACT_OUTPUT_FILES,
        }
        job_status = "COMPLETED"

    except Exception as e:
        logger.error(f"A fatal error occurred in job {job_name}: {str(e)}")
        raise

    finally:
        end_time = datetime.now()
        final_summary = {
            "job_name": job_name,
            "status": job_status,
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "duration_seconds": (end_time - start_time).total_seconds(),
            "execution_summary": execution_summary or {
                "error": "Job failed before summary could be generated."
            },
        }
        logger.info(f"Final job summary: {json.dumps(final_summary, indent=2)}")
        job.commit()


if __name__ == "__main__":
    main()
