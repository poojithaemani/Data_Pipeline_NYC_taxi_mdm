import logging
import os
import sys
import json
from typing import Iterator, Dict

from pyspark.context import SparkContext  # type: ignore[import-not-found]
from pyspark.sql import SparkSession, functions as F  # type: ignore[import-not-found]

try:
    from awsglue.context import GlueContext  # type: ignore[import-not-found]
    from awsglue.job import Job  # type: ignore[import-not-found]
    from awsglue.utils import getResolvedOptions  # type: ignore[import-not-found]
except Exception:
    # Local fallback for development/testing
    class GlueContext:  # pragma: no cover - fallback for local execution
        def __init__(self, spark_context):
            self.spark_session = spark_context.sparkSession if hasattr(spark_context, "sparkSession") else SparkSession.builder.getOrCreate()

    class Job:  # pragma: no cover - fallback for local execution
        def __init__(self, glue_context):
            self.glue_context = glue_context

        def init(self, name, args):
            self.name = name
            self.args = args

        def commit(self):
            return None

    def getResolvedOptions(args, options):
        return {opt: os.getenv(opt.upper(), f"local_{opt}") for opt in options}

import boto3

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger(__name__)

JOB_NAME = os.getenv("JOB_NAME", "vendor-etl")
DEFAULT_INPUT_PATH = os.getenv("VENDORS_CSV_PATH", "s3://your-bucket/bronze/vendors/vendors.csv")


def create_spark_session() -> SparkSession:
    logger.info("Creating Spark session for %s", JOB_NAME)
    spark = SparkSession.builder.appName(JOB_NAME).getOrCreate()
    return spark


def read_csv(spark: SparkSession, input_path: str):
    logger.info("Reading CSV from %s", input_path)
    try:
        df = (
            spark.read.option("header", "true")
            .option("inferSchema", "true")
            .option("multiLine", "false")
            .csv(input_path)
        )
        if df.rdd.isEmpty():
            raise ValueError("Input CSV is empty. No data to process.")
    except Exception as exc:
        logger.exception("Failed to read or validate input CSV from %s", input_path)
        raise RuntimeError(f"Unable to read input data: {exc}") from exc
    return df


def clean_vendors_df(df):
    # Trim whitespace for string columns, normalize null/empty -> null, cast VendorID to integer,
    # validate business key and vendor name presence, and remove duplicate VendorID rows.
    logger.info("Cleaning vendor DataFrame: trimming, handling nulls, validating required fields, removing duplicates")

    # --- 1. Normalize Column Names ---
    # Normalize column naming: allow either VendorID or vendor_id-ish
    if "VendorID" not in df.columns and "vendor_id" in df.columns:
        df = df.withColumnRenamed("vendor_id", "VendorID")

    # Normalize vendor name column if necessary
    if "vendor_name" not in df.columns and "VendorName" in df.columns:
        df = df.withColumnRenamed("VendorName", "vendor_name")

    # If vendor_name still missing, try common alternatives
    if "vendor_name" not in df.columns:
        for alt in ["vendor", "name"]:
            if alt in df.columns:
                df = df.withColumnRenamed(alt, "vendor_name")
                break

    # --- 2. Trim and Clean Data ---
    string_cols = [f.name for f in df.schema.fields if f.dataType.simpleString() == 'string']
    for col in string_cols:
        df = df.withColumn(col, F.when(F.trim(F.col(col)) == "", None).otherwise(F.trim(F.col(col))))

    # --- 3. Validate and Cast ---
    # After normalization, check that required columns exist
    required_cols = ["VendorID", "vendor_name"]
    missing_cols = [col for col in required_cols if col not in df.columns]
    if missing_cols:
        raise ValueError(f"Input CSV is missing required columns. Missing: {missing_cols}. Found: {df.columns}")

    if "VendorID" in df.columns:
        df = df.withColumn("VendorID", F.col("VendorID").cast("int"))

    df = df.filter(F.col("VendorID").isNotNull() & F.col("vendor_name").isNotNull())
    df = df.dropDuplicates(["VendorID"])

    return df


def add_record_hash(df):
    # Deterministic hash: use VendorID and vendor_name normalized
    logger.info("Generating deterministic record_hash for each row")
    # Ensure vendor_name column exists
    if "vendor_name" not in df.columns:
        # create empty vendor_name column to keep hash stable
        df = df.withColumn("vendor_name", F.lit(None).cast("string"))

    # canonicalize fields: cast VendorID to string, lower vendor_name, coalesce nulls to empty string
    concat_cols = F.concat_ws(
        "|",
        F.coalesce(F.col("VendorID").cast("string"), F.lit("")),
        F.coalesce(F.lower(F.col("vendor_name")), F.lit("")),
    )
    df = df.withColumn("record_hash", F.sha2(concat_cols, 256))
    return df


def fetch_secret(secret_arn: str) -> Dict[str, str]:
    logger.info("Fetching DB credentials from Secrets Manager: %s", secret_arn)
    client = boto3.client("secretsmanager")
    resp = client.get_secret_value(SecretId=secret_arn)
    secret = resp.get("SecretString")
    if secret is None:
        # secretsmanager can also return binary secrets
        raise RuntimeError("SecretString is empty for secret: %s" % secret_arn)
    return json.loads(secret)


def upsert_vendors_sequentially(df, db_config: Dict[str, str]) -> Dict[str, int]:
    """Iterate over records and call the upsert stored procedure using a single DB connection."""
    try:
        import pg8000
    except ImportError as e:
        logger.exception("pg8000 not available. Ensure --additional-python-modules includes pg8000.")
        raise RuntimeError("Missing required Python module: pg8000") from e

    records = df.toLocalIterator()
    counts = {"INSERTED": 0, "UPDATED": 0, "NO_CHANGE": 0, "ERROR": 0}
    conn = None

    try:
        conn = pg8000.connect(
            host=db_config.get("host"),
            port=int(db_config.get("port", 5432)),
            database=db_config.get("dbname") or db_config.get("database"),
            user=db_config.get("username") or db_config.get("user"),
            password=db_config.get("password"),
            timeout=10,
        )
        cursor = conn.cursor()

        for row in records:
            try:
                vendor_id = int(row["VendorID"])
                vendor_name = row["vendor_name"]
                record_hash = row["record_hash"]

                cursor.execute("CALL sp_upsert_vendor(%s, %s, %s, %s, %s)", (vendor_id, vendor_name, record_hash, None, None))
                result = cursor.fetchone()
                status = result[0] if result else "ERROR"

                if status in counts:
                    counts[status] += 1
                else:
                    counts["ERROR"] += 1
                    logger.warning("Row produced unexpected status: %s for vendor_id=%s", status, vendor_id)

            except Exception as row_exc:
                logger.warning("Error processing row for vendor_id=%s. Error: %s", row.get("VendorID"), str(row_exc))
                counts["ERROR"] += 1

        conn.commit()
    except Exception as exc:
        logger.exception("Database connection or execution error during sequential upsert")
        if conn:
            conn.rollback()
        raise RuntimeError(f"Failed during database operation: {exc}") from exc
    finally:
        if conn:
            conn.close()

    return counts


def main():
    spark = None
    job = None

    try:
        sc = SparkContext.getOrCreate()
        glue_context = GlueContext(sc)
        spark = glue_context.spark_session
        logger.info("Running inside Glue context")
    except Exception:
        spark = create_spark_session()
        glue_context = None
        logger.info("Running with local Spark session")

    # Accept job args
    try:
        args = getResolvedOptions(sys.argv, ["JOB_NAME", "input_path", "secret_arn"])
    except Exception:
        # Fallback defaults when running locally
        args = {
            "JOB_NAME": JOB_NAME,
            "input_path": DEFAULT_INPUT_PATH,
            "secret_arn": os.getenv("DB_SECRET_ARN"),
        }

    job_name = args.get("JOB_NAME", JOB_NAME)
    input_path = args.get("input_path") or DEFAULT_INPUT_PATH
    secret_arn = args.get("secret_arn") or None

    # Gather DB connection info
    db_config = {}
    if secret_arn:
        secret = fetch_secret(secret_arn)
        # Expect secret to contain keys: username/user, password, host, port, dbname/database
        db_config.update(secret)
    else:
        # Fallback to explicit args
        if os.getenv("DB_HOST"):
            db_config["host"] = os.getenv("DB_HOST")
            db_config["port"] = os.getenv("DB_PORT")
            db_config["dbname"] = os.getenv("DB_NAME")
            db_config["user"] = os.getenv("DB_USER")
            db_config["password"] = os.getenv("DB_PASSWORD")

    if glue_context is not None:
        job = Job(glue_context)
        job.init(job_name, args)

    logger.info("Starting vendor ETL job: %s", job_name)
    logger.info("Input path: %s", input_path)

    try:
        raw_df = read_csv(spark, input_path)
        read_count = raw_df.count()
        logger.info("Records Read: %d", read_count)

        df = clean_vendors_df(raw_df)
        processed_count = df.count()
        logger.info("Records Processed: %d", processed_count)

        df = add_record_hash(df)

        agg = upsert_vendors_sequentially(df, db_config)
        logger.info("Vendor ETL summary: INSERTED=%d UPDATED=%d NO_CHANGE=%d ERRORS=%d", agg["INSERTED"], agg["UPDATED"], agg["NO_CHANGE"], agg["ERROR"])  # noqa: E501

        # Prepare run summary and log final metrics
        run_summary = {
            "job_name": job_name,
            "input_path": input_path,
            "records_read": int(read_count),
            "records_processed": int(processed_count),
            "inserted": int(agg["INSERTED"]),
            "updated": int(agg["UPDATED"]),
            "no_change": int(agg["NO_CHANGE"]),
            "errors": int(agg["ERROR"]),
        }

        # Structured JSON summary for CloudWatch
        logger.info("Run summary: %s", json.dumps(run_summary))

        # Human-readable summary lines
        logger.info("Records Read: %d", run_summary["records_read"])
        logger.info("Records Processed: %d", run_summary["records_processed"])
        logger.info("Inserted: %d", run_summary["inserted"])
        logger.info("Updated: %d", run_summary["updated"])
        logger.info("No Change: %d", run_summary["no_change"])
        logger.info("Errors: %d", run_summary["errors"])

    except Exception as exc:
        logger.exception("Vendor ETL job failed: %s", exc)
        raise
    finally:
        if job is not None:
            job.commit()


if __name__ == "__main__":
    main()
