import io
import logging
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import urlparse

import pandas as pd
import requests

if TYPE_CHECKING:
    from .config_loader import SourceConfig
else:
    try:
        from .config_loader import SourceConfig
    except ImportError:  # pragma: no cover - fallback for direct script execution
        import importlib.util

        module_path = Path(__file__).resolve().with_name("config_loader.py")
        spec = importlib.util.spec_from_file_location("ingestion_config_loader", module_path)
        if spec is None or spec.loader is None:
            raise
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        SourceConfig = module.SourceConfig

logger = logging.getLogger(__name__)


class DataFetchError(RuntimeError):
    """Raised when a data source cannot be fetched or parsed."""


def _read_csv_from_source(source: str) -> pd.DataFrame:
    """Fetch a CSV input from either an HTTP URL or a local file path."""
    parsed_source = urlparse(source)

    if parsed_source.scheme in {"http", "https"}:
        try:
            headers = {"User-Agent": "Mozilla/5.0"}
            response = requests.get(source, headers=headers, timeout=30)
            response.raise_for_status()
        except requests.exceptions.RequestException as exc:
            logger.error("HTTP request failed while fetching CSV", extra={"source": source, "error": str(exc)})
            raise DataFetchError(f"Failed to download CSV from {source}: {exc}") from exc

        payload = response.text
    else:
        local_path = Path(source).expanduser()
        if not local_path.exists():
            logger.error("Local CSV file was not found", extra={"source": source})
            raise DataFetchError(f"Local CSV file does not exist: {source}")
        if not local_path.is_file():
            logger.error("Local CSV path is not a file", extra={"source": source})
            raise DataFetchError(f"Local CSV path is not a file: {source}")

        try:
            payload = local_path.read_text(encoding="utf-8")
        except OSError as exc:
            logger.error("Unable to read local CSV file", extra={"source": source, "error": str(exc)})
            raise DataFetchError(f"Unable to read local CSV file {source}: {exc}") from exc

    try:
        dataframe = pd.read_csv(io.StringIO(payload))
    except pd.errors.EmptyDataError as exc:
        logger.warning("The CSV payload was empty", extra={"source": source})
        return pd.DataFrame()
    except Exception as exc:  # pragma: no cover - defensive fallback
        logger.error("The CSV payload could not be parsed", extra={"source": source, "error": str(exc)})
        raise DataFetchError(f"Unable to parse CSV data from {source}: {exc}") from exc

    logger.info("CSV data fetched successfully", extra={"source": source, "rows": len(dataframe)})
    return dataframe


def _read_parquet_from_source(source: str) -> pd.DataFrame:
    """Fetch a parquet input from either an HTTP URL or a local file path."""
    parsed_source = urlparse(source)

    if parsed_source.scheme in {"http", "https"}:
        try:
            headers = {"User-Agent": "Mozilla/5.0"}
            response = requests.get(source, headers=headers, timeout=30)
            response.raise_for_status()
        except requests.exceptions.RequestException as exc:
            logger.error("HTTP request failed while fetching parquet", extra={"source": source, "error": str(exc)})
            raise DataFetchError(f"Failed to download parquet from {source}: {exc}") from exc

        payload = response.content
        try:
            dataframe = pd.read_parquet(io.BytesIO(payload))
        except Exception as exc:  # pragma: no cover - defensive fallback
            logger.error("The parquet payload could not be parsed", extra={"source": source, "error": str(exc)})
            raise DataFetchError(f"Unable to parse parquet data from {source}: {exc}") from exc
    else:
        local_path = Path(source).expanduser()
        if not local_path.exists():
            logger.error("Local parquet file was not found", extra={"source": source})
            raise DataFetchError(f"Local parquet file does not exist: {source}")
        if not local_path.is_file():
            logger.error("Local parquet path is not a file", extra={"source": source})
            raise DataFetchError(f"Local parquet path is not a file: {source}")

        try:
            dataframe = pd.read_parquet(local_path)
        except Exception as exc:  # pragma: no cover - defensive fallback
            logger.error("The parquet file could not be parsed", extra={"source": source, "error": str(exc)})
            raise DataFetchError(f"Unable to parse parquet data from {source}: {exc}") from exc

    logger.info("Parquet data fetched successfully", extra={"source": source, "rows": len(dataframe)})
    return dataframe


def fetch_data(source_config: SourceConfig) -> pd.DataFrame:
    """Fetch data from a configured source using a reusable, config-driven interface.

    The current implementation supports CSV files from HTTP URLs and local file paths.
    The design is intentionally extensible so JSON, Parquet, and API-backed sources can
    be added with a small, isolated implementation change.
    """
    source_type = (getattr(source_config, "type", "") or "").strip().lower()

    logger.info(
        "Pipeline fetch started",
        extra={
            "source": source_config.source,
            "source_type": source_type,
            "destination_table": source_config.destination_table,
        },
    )

    if source_type == "csv":
        dataframe = _read_csv_from_source(source_config.source)
        if dataframe.empty:
            logger.warning("No rows were returned from the source", extra={"source": source_config.source})
        return dataframe

    if source_type == "parquet":
        dataframe = _read_parquet_from_source(source_config.source)
        if dataframe.empty:
            logger.warning("No rows were returned from the source", extra={"source": source_config.source})
        return dataframe

    logger.error("Unsupported or unimplemented source type", extra={"source_type": source_type})
    return pd.DataFrame()


if __name__ == "__main__":
    import logging

    logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
    try:
        from .config_loader import IngestionConfig, load_config

        project_root = Path(__file__).resolve().parents[2]
        config_file_path = project_root / "configs" / "sources.yaml"
        ingestion_config: IngestionConfig = load_config(str(config_file_path))
        taxi_zones_config = ingestion_config.sources.get("taxi_zones")

        if taxi_zones_config:
            dataframe = fetch_data(taxi_zones_config)
            logger.info("Fetch example completed", extra={"rows": len(dataframe), "columns": list(dataframe.columns)})
        else:
            logger.error("The taxi_zones source was not found in the configuration")
    except Exception as exc:  # pragma: no cover - example only
        logger.error("Fetch example failed", extra={"error": str(exc)})
