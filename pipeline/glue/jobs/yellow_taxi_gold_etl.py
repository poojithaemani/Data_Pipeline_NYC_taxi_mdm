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


JOB_NAME = os.getenv("JOB_NAME", "yellow-taxi-gold-etl")
SILVER_PATH = os.getenv("SILVER_PATH", "s3://your-bucket/silver/yellow-taxi")
GOLD_PATH = os.getenv("GOLD_PATH", "s3://your-bucket/gold/yellow-taxi")

REQUIRED_SILVER_COLUMNS = [
    "VendorID",
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime",
    "fare_amount",
    "trip_distance",
    "tip_amount",
    "passenger_count",
    "payment_type",
    "PULocationID",
    "DOLocationID",
]


def create_spark_session() -> SparkSession:
    """Create a Spark session configured for Delta Lake and Glue execution."""
    logger.info("Creating Spark session")
    try:
        spark = (
            SparkSession.builder.appName(JOB_NAME)
            .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
            .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
            .getOrCreate()
        )
        logger.info("Spark session created successfully")
        return spark
    except Exception as exc:
        logger.exception("Failed to create Spark session")
        raise RuntimeError(f"Unable to create Spark session: {exc}") from exc


def read_silver_data(spark: SparkSession, input_path: str) -> DataFrame:
    """Read the curated Silver Delta data from S3."""
    logger.info("Reading Silver data from %s", input_path)
    try:
        return spark.read.format("delta").load(input_path)
    except Exception as exc:
        logger.exception("Failed to read Silver data from %s", input_path)
        raise RuntimeError(f"Unable to read Silver data: {exc}") from exc


def _validate_required_columns(df: DataFrame, required_columns: list[str]) -> None:
    """Ensure the Silver dataset contains the columns needed for the requested transformation."""
    missing_columns = [column for column in required_columns if column not in df.columns]
    if missing_columns:
        raise ValueError(f"Required columns missing: {missing_columns}")


def transform_daily_summary(df: DataFrame) -> DataFrame:
    """Create a daily business summary for reporting and finance use cases."""
    logger.info("Creating daily revenue summary")
    _validate_required_columns(df, ["tpep_pickup_datetime", "fare_amount", "trip_distance"])

    return (
        df.withColumn("trip_date", F.to_date(F.col("tpep_pickup_datetime")))
        .groupBy("trip_date")
        .agg(
            F.count("*").alias("total_trips"),
            F.sum("fare_amount").alias("total_revenue"),
            F.avg("fare_amount").alias("average_fare"),
            F.avg("trip_distance").alias("average_distance"),
        )
    )


def transform_vendor_summary(df: DataFrame) -> DataFrame:
    """Create a vendor performance summary for operations monitoring."""
    logger.info("Creating vendor performance summary")
    _validate_required_columns(df, ["VendorID", "fare_amount", "tip_amount", "trip_distance", "tpep_pickup_datetime"])

    return (
        df.withColumn("trip_date", F.to_date(F.col("tpep_pickup_datetime")))
        .groupBy("trip_date", "VendorID")
        .agg(
            F.count("*").alias("trip_count"),
            F.sum("fare_amount").alias("total_revenue"),
            F.avg("tip_amount").alias("average_tip"),
            F.avg("trip_distance").alias("average_trip_distance"),
        )
        .orderBy("trip_date", "VendorID")
    )


def transform_borough_summary(df: DataFrame) -> DataFrame:
    """Create a location-based performance summary for geographic analysis."""
    logger.info("Creating borough performance summary")
    _validate_required_columns(df, ["tpep_pickup_datetime", "PULocationID", "DOLocationID", "fare_amount"])

    return (
        df.withColumn("trip_date", F.to_date(F.col("tpep_pickup_datetime")))
        .withColumn("pickup_location_id", F.col("PULocationID"))
        .withColumn("dropoff_location_id", F.col("DOLocationID"))
        .groupBy("trip_date", "pickup_location_id", "dropoff_location_id")
        .agg(
            F.count("*").alias("trip_count"),
            F.sum("fare_amount").alias("total_revenue"),
            F.avg("fare_amount").alias("average_fare"),
        )
        .orderBy("trip_date", "pickup_location_id", "dropoff_location_id")
    )


def transform_payment_summary(df: DataFrame) -> DataFrame:
    """Create a payment type summary for finance and customer behavior analysis."""
    logger.info("Creating payment type summary")
    _validate_required_columns(df, ["payment_type", "fare_amount", "tpep_pickup_datetime"])

    return (
        df.withColumn("trip_date", F.to_date(F.col("tpep_pickup_datetime")))
        .groupBy("trip_date", "payment_type")
        .agg(
            F.count("*").alias("trip_count"),
            F.sum("fare_amount").alias("total_amount"),
            F.avg("fare_amount").alias("average_fare"),
        )
        .orderBy("trip_date", "trip_count", ascending=False)
    )


def transform_hourly_summary(df: DataFrame) -> DataFrame:
    """Create an hourly trip demand summary for operational planning."""
    logger.info("Creating hourly trip summary")
    _validate_required_columns(df, ["tpep_pickup_datetime", "fare_amount"])

    return (
        df.withColumn("trip_date", F.to_date(F.col("tpep_pickup_datetime")))
        .withColumn("pickup_hour", F.hour(F.col("tpep_pickup_datetime")))
        .groupBy("trip_date", "pickup_hour")
        .agg(
            F.count("*").alias("trip_count"),
            F.avg("fare_amount").alias("average_fare"),
        )
        .orderBy("trip_date", "pickup_hour")
    )


def write_gold_data(gold_datasets: dict[str, tuple[DataFrame, str, list[str]]]) -> None:
    """Write each Gold dataset to Delta Lake in S3."""
    for dataset_name, (dataset_df, output_path, partition_columns) in gold_datasets.items():
        logger.info("Writing %s to %s", dataset_name, output_path)
        try:
            write_builder = (
                dataset_df.write.format("delta")
                .mode("overwrite")
                .option("compression", "snappy")
            )

            if partition_columns:
                write_builder = write_builder.partitionBy(*partition_columns)

            write_builder.save(output_path)
            logger.info("Successfully wrote %s", dataset_name)
        except Exception as exc:
            logger.exception("Failed to write Gold dataset: %s", dataset_name)
            raise RuntimeError(f"Unable to write Gold dataset {dataset_name}: {exc}") from exc


def main() -> None:
    """Orchestrate the Silver-to-Gold Glue ETL job."""
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
        args = getResolvedOptions(sys.argv, ["JOB_NAME", "silver_path", "gold_path"])
    except Exception:
        args = {
            "JOB_NAME": JOB_NAME,
            "silver_path": SILVER_PATH,
            "gold_path": GOLD_PATH,
        }

    job_name = args.get("JOB_NAME", JOB_NAME)
    silver_path = args.get("silver_path", SILVER_PATH)
    gold_path = args.get("gold_path", GOLD_PATH)

    if glue_context is not None:
        job = Job(glue_context)
        job.init(job_name, args)

    logger.info("Starting Glue ETL job: %s", job_name)
    logger.info("Silver path: %s", silver_path)
    logger.info("Gold path: %s", gold_path)

    try:
        silver_df = read_silver_data(spark, silver_path)

        daily_summary_df = transform_daily_summary(silver_df)
        vendor_summary_df = transform_vendor_summary(silver_df)
        borough_summary_df = transform_borough_summary(silver_df)
        payment_summary_df = transform_payment_summary(silver_df)
        hourly_summary_df = transform_hourly_summary(silver_df)

        gold_datasets = {
            "daily_summary": (
                daily_summary_df,
                f"{gold_path}/daily_summary",
                ["trip_date"],
            ),
            "vendor_summary": (
                vendor_summary_df,
                f"{gold_path}/vendor_summary",
                ["trip_date"],
            ),
            "borough_summary": (
                borough_summary_df,
                f"{gold_path}/borough_summary",
                ["trip_date"],
            ),
            "payment_summary": (
                payment_summary_df,
                f"{gold_path}/payment_summary",
                ["trip_date"],
            ),
            "hourly_summary": (
                hourly_summary_df,
                f"{gold_path}/hourly_summary",
                ["trip_date"],
            ),
        }

        write_gold_data(gold_datasets)
        logger.info("Glue ETL job completed successfully")
    except Exception as exc:
        logger.exception("Glue ETL job failed")
        raise RuntimeError(f"Glue ETL job failed: {exc}") from exc
    finally:
        if job is not None:
            job.commit()


if __name__ == "__main__":
    main()
