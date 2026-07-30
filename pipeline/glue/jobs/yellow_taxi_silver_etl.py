import logging
import os
import sys

from pyspark.context import SparkContext  # type: ignore[import-not-found]
from pyspark.sql import DataFrame, SparkSession, functions as F  # type: ignore[import-not-found]
from pyspark.sql.types import DoubleType, IntegerType  # type: ignore[import-not-found]

try:
    from awsglue.context import GlueContext  # type: ignore[import-not-found]
    from awsglue.job import Job  # type: ignore[import-not-found]
    from awsglue.utils import getResolvedOptions  # type: ignore[import-not-found]
except ImportError:
    from pyspark.context import SparkContext  # type: ignore[import-not-found]

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


logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger(__name__)


BRONZE_PATH = os.getenv("BRONZE_PATH", "s3://your-bucket/bronze/yellow-taxi")
SILVER_PATH = os.getenv("SILVER_PATH", "s3://your-bucket/silver/yellow-taxi")
JOB_NAME = os.getenv("JOB_NAME", "yellow-taxi-silver-etl")

REQUIRED_COLUMNS = [
    "VendorID",
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime",
    "PULocationID",
    "DOLocationID",
    "trip_distance",
    "fare_amount",
    "passenger_count",
]

MANDATORY_COLUMNS = [
    "VendorID",
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime",
    "PULocationID",
    "DOLocationID",
]


def create_spark_session() -> SparkSession:
    """Create a Spark session for Glue or local execution."""
    logger.info("Creating Spark session")
    try:
        spark = SparkSession.builder.appName(JOB_NAME)
        spark = (
            spark.config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
            .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
            .getOrCreate()
        )
        logger.info("Spark session created successfully")
        return spark
    except Exception as exc:
        logger.exception("Failed to create Spark session")
        raise RuntimeError(f"Unable to create Spark session: {exc}") from exc


def read_bronze_data(spark: SparkSession, input_path: str) -> DataFrame:
    """Read the Bronze Parquet data from S3."""
    logger.info("Reading Bronze data from %s", input_path)
    try:
        return (
            spark.read.format("parquet")
            .option("mergeSchema", "true")
            .load(input_path)
        )
    except Exception as exc:
        logger.exception("Failed to read Bronze data from %s", input_path)
        raise RuntimeError(f"Unable to read Bronze data: {exc}") from exc


def clean_data(df: DataFrame) -> DataFrame:
    """Remove duplicates and enforce the Silver-layer data quality rules."""
    logger.info("Applying Silver-layer cleaning rules")
    try:
        missing_columns = [column for column in REQUIRED_COLUMNS if column not in df.columns]
        if missing_columns:
            raise ValueError(f"Required columns missing: {missing_columns}")

        input_row_count = df.count()
        deduplicated_df = df.dropDuplicates()
        deduplicated_row_count = deduplicated_df.count()

        cleaned_df = (
            deduplicated_df.dropna(subset=MANDATORY_COLUMNS)
            .filter(
                (F.col("trip_distance") >= 0)
                & (F.col("fare_amount") >= 0)
                & (F.col("passenger_count") > 0)
                & (F.col("tpep_pickup_datetime") <= F.col("tpep_dropoff_datetime"))
            )
        )

        cleaned_df = (
            cleaned_df.withColumn("VendorID", F.col("VendorID").cast(IntegerType()))
            .withColumn("PULocationID", F.col("PULocationID").cast(IntegerType()))
            .withColumn("DOLocationID", F.col("DOLocationID").cast(IntegerType()))
            .withColumn("passenger_count", F.col("passenger_count").cast(IntegerType()))
            .withColumn("trip_distance", F.col("trip_distance").cast(DoubleType()))
            .withColumn("fare_amount", F.col("fare_amount").cast(DoubleType()))
            .withColumn("tpep_pickup_datetime", F.to_timestamp(F.col("tpep_pickup_datetime")))
            .withColumn("tpep_dropoff_datetime", F.to_timestamp(F.col("tpep_dropoff_datetime")))
        )

        cleaned_row_count = cleaned_df.count()
        duplicates_removed = input_row_count - deduplicated_row_count
        invalid_rows_removed = deduplicated_row_count - cleaned_row_count

        logger.info("Bronze records read      : %s", f"{input_row_count:,}")
        logger.info("Duplicate rows removed   : %s", f"{duplicates_removed:,}")
        logger.info("Invalid rows removed     : %s", f"{invalid_rows_removed:,}")
        logger.info("Cleaning rules completed successfully")
        return cleaned_df
    except Exception as exc:
        logger.exception("Cleaning step failed")
        raise RuntimeError(f"Unable to clean data: {exc}") from exc


def add_partition_columns(df: DataFrame) -> DataFrame:
    """Create partition columns from the pickup timestamp."""
    logger.info("Adding partition columns")
    try:
        return (
            df.withColumn("pickup_year", F.year(F.col("tpep_pickup_datetime")))
            .withColumn("pickup_month", F.month(F.col("tpep_pickup_datetime")))
        )
    except Exception as exc:
        logger.exception("Partition column creation failed")
        raise RuntimeError(f"Unable to add partition columns: {exc}") from exc


def write_silver_data(df: DataFrame, output_path: str) -> None:
    """Write the cleaned data to the Silver layer in Delta format."""
    logger.info("Writing Silver data to %s", output_path)
    try:
        (
            df.write.format("delta")
            .mode("overwrite")
            .partitionBy("pickup_year", "pickup_month")
            .option("compression", "snappy")
            .save(output_path)
        )
        logger.info("Silver data written successfully")
    except Exception as exc:
        logger.exception("Failed to write Silver data")
        raise RuntimeError(f"Unable to write Silver data: {exc}") from exc


def main() -> None:
    """Orchestrate the Bronze-to-Silver Glue ETL job."""
    spark = None
    job = None

    try:
        spark_context = SparkContext.getOrCreate()
        glue_context = GlueContext(spark_context)
        spark = glue_context.spark_session
        logger.info("Using Glue-provided Spark session")
    except Exception:
        spark = create_spark_session()
        glue_context = None
        logger.info("Falling back to local Spark session")

    try:
        args = getResolvedOptions(sys.argv, ["JOB_NAME", "bronze_path", "silver_path"])
    except Exception:
        args = {
            "JOB_NAME": JOB_NAME,
            "bronze_path": BRONZE_PATH,
            "silver_path": SILVER_PATH,
        }

    job_name = args.get("JOB_NAME", JOB_NAME)
    bronze_path = args.get("bronze_path", BRONZE_PATH)
    silver_path = args.get("silver_path", SILVER_PATH)

    if glue_context is not None:
        job = Job(glue_context)
        job.init(job_name, args)

    logger.info("Starting Glue ETL job: %s", job_name)
    logger.info("Bronze path: %s", bronze_path)
    logger.info("Silver path: %s", silver_path)

    try:
        raw_df = read_bronze_data(spark, bronze_path)
        cleaned_df = clean_data(raw_df)
        partitioned_df = add_partition_columns(cleaned_df)
        silver_row_count = partitioned_df.count()
        write_silver_data(partitioned_df, silver_path)
        logger.info("Silver records written   : %s", f"{silver_row_count:,}")
        logger.info("Glue ETL job completed successfully")
    except Exception as exc:
        logger.exception("Glue ETL job failed")
        raise RuntimeError(f"Glue ETL job failed: {exc}") from exc
    finally:
        if job is not None:
            job.commit()


if __name__ == "__main__":
    main()
