"""
Pipeline Orchestrator

Runs the complete reference data ingestion pipeline for all configured sources.

Pipeline:
    Fetch Data
        ↓
    Validate Schema
        ↓
    Clean Data
        ↓
    Upload to S3
        ↓
    Load into PostgreSQL
"""

import logging
import time
from pathlib import Path
import os

from .config_loader import load_config, IngestionConfig
from .fetch_data import fetch_data, DataFetchError
from .validate_schema import validate_schema
from .clean_data import clean_data
from .upload_to_s3 import upload_to_s3
from .load_to_postgre import load_to_postgres

logger = logging.getLogger(__name__)


def _build_s3_object_key(source_name: str, source_config, source_type: str) -> str:
    """Build an S3 object key that preserves the existing reference-data layout and supports transactions."""
    file_extension = "parquet" if source_type == "parquet" else "csv"
    configured_path = getattr(source_config, "destination_path", None)
    if configured_path:
        return f"{configured_path.rstrip('/')}/{source_name}.{file_extension}"

    prefix = "bronze/transactions" if source_type == "parquet" else "bronze/reference"
    return f"{prefix}/{source_name}/{source_name}.{file_extension}"


def run_pipeline() -> None:
    """
    Execute the complete ingestion pipeline for all configured sources.
    """
    start_time = time.time()
    logger.info("Starting ingestion pipeline...")

    try:
        # Load configuration
        project_root = Path(__file__).resolve().parents[2]
        config_file_path = project_root / "configs" / "source.yaml"
        ingestion_config: IngestionConfig = load_config(str(config_file_path))

        # Get S3 bucket from environment variables
        s3_bucket = os.getenv("AWS_S3_BUCKET")
        if not s3_bucket:
            logger.error("AWS_S3_BUCKET environment variable not set. S3 upload will fail.")
            # Depending on requirements, you might want to exit here
            # return

        if not ingestion_config.sources:
            logger.warning("No sources found in the configuration. Pipeline will exit.")
            return

        for source_name, source_config in ingestion_config.sources.items():
            source_start_time = time.time()
            logger.info(f"--- Starting processing for source: {source_name} ---")

            try:
                source_type = (getattr(source_config, "type", "") or "").strip().lower()

                # Step 1: Fetch latest source data
                logger.info("Step 1: Fetching data...")
                raw_df = fetch_data(source_config)
                if raw_df.empty:
                    logger.warning(f"No data fetched for source '{source_name}'. Skipping.")
                    continue

                # Step 2: Validate schema
                logger.info("Step 2: Validating schema...")
                validation_report = validate_schema(raw_df, source_config)
                if not validation_report["is_valid"]:
                    logger.error(f"Schema validation failed for '{source_name}': {validation_report['summary']}")
                    logger.error("Skipping further processing for this source.")
                    continue

                if source_type == "parquet":
                    logger.info("Parquet source detected; skipping cleaning and database load.")
                    clean_df = raw_df
                else:
                    # Step 3: Clean data
                    logger.info("Step 3: Cleaning data...")
                    clean_df = clean_data(raw_df, source_config)

                # Step 4: Upload data to S3
                if s3_bucket:
                    logger.info("Step 4: Uploading to S3...")
                    s3_object_key = _build_s3_object_key(source_name, source_config, source_type)

                    upload_successful = upload_to_s3(clean_df, s3_bucket, s3_object_key)
                    if not upload_successful:
                        logger.error(f"S3 upload failed for '{source_name}'.")
                        continue
                else:
                    logger.warning("Skipping S3 upload because AWS_S3_BUCKET is not set.")

                db_host = os.getenv("DB_HOST")
                destination_table = getattr(source_config, "destination_table", None)

                if source_type != "parquet" and destination_table:
                    if not db_host:
                        logger.warning(
                            "Skipping PostgreSQL load because DB_HOST environment variable is not set.",
                        )
                        continue

                    # Step 5: Load into PostgreSQL
                    logger.info("Step 5: Loading to PostgreSQL...")
                    load_to_postgres(
                        clean_df,
                        destination_table,
                        getattr(source_config, "primary_key", ""),
                    )
                else:
                    logger.info("Skipping PostgreSQL load because no destination table is configured.")

                source_elapsed = round(time.time() - source_start_time, 2)
                logger.info(f"--- Finished processing for source: {source_name} in {source_elapsed}s ---")

            except DataFetchError as e:
                logger.error(f"Failed to fetch data for {source_name}: {e}")
            except Exception as e:
                logger.exception(f"An unexpected error occurred while processing source {source_name}: {e}")

        total_elapsed = round(time.time() - start_time, 2)
        logger.info("Pipeline completed.")
        logger.info("Total execution time: %.2f seconds", total_elapsed)

    except Exception as e:
        logger.exception("A critical error occurred during pipeline initialization: %s", e)
        raise


if __name__ == "__main__":
    # Add project root to Python path
    import sys
    from pathlib import Path
    project_root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(project_root))

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
    )
    run_pipeline()
