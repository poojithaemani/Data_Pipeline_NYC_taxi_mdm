import ssl
import sys
import json
from datetime import datetime

import pg8000.dbapi
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, md5, concat_ws, upper, trim, coalesce, lit
from pyspark.sql.types import (StructType, StructField, IntegerType, StringType)


def validate_schema(df, required_columns, logger):
    """
    Validates that the DataFrame contains all required columns, raising an error if not.

    Args:
        df (DataFrame): The DataFrame to validate.
        required_columns (set): A set of column names that must be present.
        logger: The logger to use for output.
    """
    missing_columns = required_columns - set(df.columns)
    if missing_columns:
        error_message = f"Input schema validation failed. Missing columns: {list(missing_columns)}"
        logger.error(error_message)
        raise ValueError(error_message)
    logger.info("Input schema validation successful.")


def process_source_data(spark, input_path, logger):
    """
    Reads, cleans, and standardizes the source CSV data, and generates a record hash.

    Args:
        spark (SparkSession): The Spark session.
        input_path (str): The S3 path to the source CSV file.
        logger: The logger to use for output.

    Returns:
        DataFrame: A Spark DataFrame with cleaned data and a 'record_hash' column.
    """
    # --- Read source data ---
    # Define an explicit schema for the source CSV. This is more robust than `inferSchema`
    # as it prevents schema inference errors and ensures type consistency.
    source_schema = StructType([
        StructField("LocationID", IntegerType(), True),
        StructField("Borough", StringType(), True),
        StructField("Zone", StringType(), True),
        StructField("service_zone", StringType(), True),
    ])

    logger.info(f"Reading source data from: {input_path}")
    source_df = spark.read.option("header", "true").schema(source_schema).csv(input_path)

    # --- Schema Validation ---
    required_columns = {"LocationID", "Borough", "Zone", "service_zone"}
    validate_schema(source_df, required_columns, logger)

    # --- Standardize data and Generate record hash ---
    #    - Trim whitespace and convert to uppercase for consistency.
    #    - Coalesce null values to an empty string before hashing to ensure determinism.
    #    - The hash is based on the business key and all descriptive attributes.
    logger.info("Standardizing data and generating record hash.")
    standardized_df = (
        source_df.withColumn("location_id", col("LocationID").cast("int"))
        .withColumn("borough", upper(trim(col("Borough"))))
        .withColumn("zone", upper(trim(col("Zone"))))
        .withColumn("service_zone", upper(trim(col("service_zone"))))
        .withColumn(
            "record_hash",
            md5(
                concat_ws(
                    "|",
                    col("location_id"),
                    coalesce(col("borough"), lit("")),
                    coalesce(col("zone"), lit("")),
                    coalesce(col("service_zone"), lit("")),
                )
            ),
        )
    )

    # Select only the columns needed for the downstream stored procedure call
    final_df = standardized_df.select(
        "location_id", "borough", "zone", "service_zone", "record_hash"
    )

    # For a small dataset, a direct count on the final DataFrame is efficient.
    record_count = final_df.count()
    logger.info(f"Successfully processed {record_count} records from source.")

    return final_df


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


def get_db_connection(db_args, logger):
    """
    Establishes and returns a connection to the PostgreSQL database.

    Args:
        db_args (dict): A dictionary containing database connection parameters.
        logger: The logger to use for output.

    Returns:
        pg8000.dbapi.Connection: A database connection object.
    """
    required_keys = {"DB_HOST", "DB_PORT", "DB_NAME", "SECRET_ARN"}
    if not required_keys.issubset(db_args.keys()):
        raise ValueError(f"Missing one or more required DB arguments: {required_keys}")

    username, password = _db_credentials(db_args["SECRET_ARN"], logger)

    # --- Connect to PostgreSQL ---
    logger.info(f"Connecting to database host: {db_args['DB_HOST']}")
    try:
        conn = pg8000.dbapi.connect(
            host=db_args["DB_HOST"],
            port=int(db_args["DB_PORT"]),
            database=db_args["DB_NAME"],
            user=username,
            password=password,
            ssl_context=_ssl_context(),
        )
        logger.info("Database connection successful.")
        return conn
    except Exception as e:
        logger.error(f"Database connection failed: {str(e)}")
        raise


def upsert_records(df, db_args, logger):
    """
    Iterates through a DataFrame and calls the SCD2 stored procedure for each row.

    Args:
        df (DataFrame): The DataFrame containing records to upsert.
        db_args (dict): Database connection parameters.
        logger: The logger to use for output.

    Returns:
        dict: A summary dictionary with counts of operations.
    """
    summary = {"inserted": 0, "updated": 0, "no_change": 0, "errors": 0}
    conn = None

    try:
        conn = get_db_connection(db_args, logger)
        # Use toLocalIterator to process partitions sequentially on the driver,
        # avoiding OOM errors by not collecting the entire dataset at once.
        for row in df.toLocalIterator():
            cursor = None
            try:
                # --- Call stored procedure for each row ---
                # The stored procedure handles the entire SCD2 transaction atomically.
                cursor = conn.cursor()
                # sp_upsert_golden_zone takes 7 parameters: 5 IN, then OUT p_status,
                # then p_effective_date. PostgreSQL requires a placeholder argument for
                # OUT parameters in CALL, so both trailing values are passed as NULL.
                cursor.execute(
                    "CALL sp_upsert_golden_zone(%s, %s, %s, %s, %s, %s, %s)",
                    (
                        row["location_id"],
                        row["borough"],
                        row["zone"],
                        row["service_zone"],
                        row["record_hash"],
                        None,
                        None,
                    ),
                )
                # The status is returned as the last output parameter.
                result = cursor.fetchone()
                status = result[0] if result else None

                if status == "INSERTED":
                    summary["inserted"] += 1
                elif status == "UPDATED":
                    summary["updated"] += 1
                elif status == "NO_CHANGE":
                    summary["no_change"] += 1
                else:
                    # An unrecognised status means the procedure did not report a
                    # known outcome; count it so the row is never silently dropped.
                    summary["errors"] += 1
                    logger.warning(
                        f"Unexpected status '{status}' for location_id={row['location_id']}"
                    )

                # Commit after each successful procedure call.
                conn.commit()

            except Exception as e:
                summary["errors"] += 1
                if conn:
                    conn.rollback() # Rollback the failed transaction

                # Log the error with structured context for better debugging in CloudWatch.
                log_payload = {
                    "status": "ERROR",
                    "error_message": str(e),
                    "location_id": row["location_id"],
                    "record_hash": row["record_hash"],
                }
                logger.error(json.dumps(log_payload))
            finally:
                if cursor:
                    cursor.close()
    finally:
        if conn:
            conn.close()
            logger.info("Database connection closed.")

    return summary


def main():
    """
    Main entry point for the Glue ETL job.
    """
    # 1. Standard AWS Glue Initialization
    job_args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "input_path",
            "DB_HOST",
            "DB_PORT",
            "DB_NAME",
            "SECRET_ARN",
        ],
    )
    job_name = job_args["JOB_NAME"]

    spark = SparkSession.builder.getOrCreate()
    glue_context = GlueContext(spark.sparkContext)
    job = Job(glue_context)
    job.init(job_name, job_args)

    # Use the official Glue logger after context initialization.
    logger = glue_context.get_logger()

    start_time = datetime.now()
    job_status = "FAILED"
    logger.info(f"Starting Glue job: {job_name}")

    try:
        # 2. Process Source Data
        processed_df = process_source_data(spark, job_args["input_path"], logger)

        # 3. Upsert to Database
        # The DataFrame is passed to the upsert function which will iterate and call the SP.
        execution_summary = upsert_records(processed_df, job_args, logger)
        job_status = "COMPLETED"

    except Exception as e:
        # Catch fatal errors (e.g., S3 access denied, DB connection failed)
        logger.error(f"A fatal error occurred in job {job_name}: {str(e)}")
        # Re-raise the exception to mark the Glue job as FAILED.
        raise

    finally:
        # --- Log summary and commit job ---
        # This block executes whether the job succeeds or fails (after the try/except).
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()

        final_summary = {
            "job_name": job_name,
            "status": job_status,
            "start_time": start_time.isoformat(),
            "end_time": end_time.isoformat(),
            "duration_seconds": duration,
            "execution_summary": execution_summary if "execution_summary" in locals() else {"error": "Job failed before summary could be generated."}
        }

        # Use json.dumps for a structured, searchable log entry in CloudWatch.
        logger.info(f"Final job summary: {json.dumps(final_summary, indent=2)}")

        # The job.commit() call signals to Glue that the job has completed.
        job.commit()

if __name__ == "__main__":
    main()