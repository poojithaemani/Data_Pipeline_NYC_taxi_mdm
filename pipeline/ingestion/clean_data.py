import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

import pandas as pd

from .config_loader import SourceConfig

# --- Logger Setup ---
logger = logging.getLogger(__name__)

# --- Cleaning Functions ---

def trim_whitespace(df: pd.DataFrame, columns: List[str] = None) -> pd.DataFrame:
    """
    Trims leading and trailing whitespace from string columns in the DataFrame.

    Args:
        df (pd.DataFrame): The input DataFrame.
        columns (List[str], optional): A list of column names to process.
                                       If None, all string columns will be processed.

    Returns:
        pd.DataFrame: The DataFrame with whitespace trimmed from specified string columns.
    """
    df_cleaned = df.copy()
    if columns is None:
        string_cols = df_cleaned.select_dtypes(include=['object', 'string']).columns
    else:
        string_cols = [col for col in columns if col in df_cleaned.columns and df_cleaned[col].dtype in ['object', 'string']]
        if len(string_cols) < len(columns):
            logger.warning(f"Some specified columns for trimming are not present or not string type: {[col for col in columns if col not in string_cols]}")

    if len(string_cols) == 0:
        logger.info("No string columns found for whitespace trimming or all specified columns are missing/not string type.")
        return df_cleaned

    for col in string_cols:
        df_cleaned[col] = df_cleaned[col].apply(
        lambda x: x.strip() if isinstance(x, str) else x
    )
    
    logger.info(f"Trimmed whitespace from columns: {', '.join(string_cols)}")
    return df_cleaned

def remove_duplicate_rows(df: pd.DataFrame, subset_cols: List[str] = None, keep: str = 'first') -> pd.DataFrame:
    """
    Removes duplicate rows from the DataFrame.

    Args:
        df (pd.DataFrame): The input DataFrame.
        subset_cols (List[str], optional): A list of column names to consider for identifying duplicates.
                                           If None, all columns are considered.
        keep (str): Determines which duplicates to mark. 'first', 'last', or False.
                    'first': Mark duplicates as True except for the first occurrence.
                    'last': Mark duplicates as True except for the last occurrence.
                    False: Mark all duplicates as True.

    Returns:
        pd.DataFrame: The DataFrame with duplicate rows removed.
    """
    initial_rows = len(df)
    df_cleaned = df.drop_duplicates(subset=subset_cols, keep=keep)
    rows_removed = initial_rows - len(df_cleaned)
    if rows_removed > 0:
        if subset_cols:
            logger.info(f"Removed {rows_removed} duplicate rows based on columns: {', '.join(subset_cols)} (keeping '{keep}').")
        else:
            logger.info(f"Removed {rows_removed} duplicate rows based on all columns (keeping '{keep}').")
    else:
        logger.info("No duplicate rows found to remove.")
    return df_cleaned

def rename_columns(df: pd.DataFrame, source_config: SourceConfig) -> pd.DataFrame:
    """
    Renames columns based on the mapping provided in the source configuration.

    Args:
        df (pd.DataFrame): The input DataFrame.
        source_config (SourceConfig): The configuration for the data source.

    Returns:
        pd.DataFrame: The DataFrame with renamed columns.
    """
    if hasattr(source_config, 'column_mapping') and source_config.column_mapping:
        df_cleaned = df.rename(columns=source_config.column_mapping)
        logger.info("Renamed columns based on the provided mapping: %s", source_config.column_mapping)
        return df_cleaned
    else:
        logger.warning("No column mapping found in the source configuration. Skipping column renaming.")
        return df

# --- Main Cleaning Orchestrator ---

def clean_data(df: pd.DataFrame, source_config: SourceConfig) -> pd.DataFrame:
    """
    Orchestrates data cleaning operations for a DataFrame.

    - Removes duplicate rows
    - Renames columns based on mapping
    - Trims whitespace from string columns
    - Fills missing values in specific columns

    Args:
        df (pd.DataFrame): The DataFrame to clean.
        source_config (SourceConfig): The configuration for the data source.

    Returns:
        pd.DataFrame: The cleaned DataFrame.
    """
    logger.info(f"Starting data cleaning for '{source_config.destination_table}' (initial rows: {len(df)})")
    
    df_cleaned = df.copy()

    # 1. Remove duplicate rows
    df_cleaned = remove_duplicate_rows(df_cleaned)

    # 2. Rename columns
    df_cleaned = rename_columns(df_cleaned, source_config)

    # 3. Trim whitespace from all string columns
    df_cleaned = trim_whitespace(df_cleaned)

    # 4. Fill missing values
    # The user requested to fill missing values for these specific columns
    fill_values = {
        "borough": "Unknown",
        "zone": "Unknown",
        "service_zone": "Unknown"
    }
    for col, value in fill_values.items():
        if col in df_cleaned.columns:
            df_cleaned[col] = (
                df_cleaned[col]
                .replace("", pd.NA)
                .fillna(value)
            )
            logger.info("Filled missing values in '%s' with '%s'.", col, value)

    logger.info(f"Data cleaning completed for '{source_config.destination_table}' (final rows: {len(df_cleaned)})")
    return df_cleaned

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

    try:
        import sys
        
        project_root = Path(__file__).resolve().parents[2]
        sys.path.insert(0, str(project_root))

        from pipeline.ingestion.config_loader import load_config
        from pipeline.ingestion.fetch_data import fetch_data

        ingestion_config = load_config(str(project_root / "configs" / "sources.yaml"))
        taxi_zones_config = ingestion_config.sources.get("taxi_zones")

        if taxi_zones_config:
            logger.info("Running clean_data demo for taxi_zones")
            df_fetched = fetch_data(taxi_zones_config)
            df_test_clean = df_fetched.copy()

            # Introduce some dirtiness for testing
            if "Zone" in df_test_clean.columns:
                df_test_clean["Zone"] = df_test_clean["Zone"].apply(lambda value: "  " + str(value) + "  ")
            df_test_clean = pd.concat([df_test_clean, df_test_clean.head(1)], ignore_index=True)
            if "service_zone" in df_test_clean.columns:
                df_test_clean.loc[2, "service_zone"] = None

            logger.info("DataFrame before cleaning (rows: %d)", len(df_test_clean))
            df_cleaned = clean_data(df_test_clean, taxi_zones_config)
            logger.info(
                "Cleaning demonstration completed (rows before: %d, rows after: %d)",
                len(df_test_clean),
                len(df_cleaned),
            )
            print("\nCleaned DataFrame sample:")
            print(df_cleaned.head())
        else:
            logger.error("The taxi_zones source was not found in the configuration")
    except Exception as exc:  # pragma: no cover - example only
        logger.error("Cleaning example failed", extra={"error": str(exc)})