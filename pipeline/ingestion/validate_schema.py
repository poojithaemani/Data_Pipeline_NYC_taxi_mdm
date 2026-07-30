import logging
import pandas as pd
from typing import List, Dict, Any, Tuple
import copy

from .config_loader import SourceConfig

# --- Logger Setup ---
logger = logging.getLogger(__name__)

# --- Validation Functions ---

def validate_required_columns(df: pd.DataFrame, required_columns: List[str]) -> Tuple[bool, List[str]]:
    """
    Checks if all required columns are present in the DataFrame.

    Args:
        df (pd.DataFrame): The DataFrame to validate.
        required_columns (List[str]): A list of column names that must be present.

    Returns:
        Tuple[bool, List[str]]: A tuple containing:
                                - bool: True if all required columns are present, False otherwise.
                                - List[str]: A list of missing columns.
    """
    missing_columns = [col for col in required_columns if col not in df.columns]
    if missing_columns:
        logger.warning(f"Missing required columns: {', '.join(missing_columns)}")
        return False, missing_columns
    logger.info("All required columns are present.")
    return True, []

def detect_duplicates(df: pd.DataFrame, primary_key: str) -> pd.DataFrame:
    """
    Detects and returns duplicate rows based on the primary key.

    Args:
        df (pd.DataFrame): The DataFrame to check for duplicates.
        primary_key (str): The column designated as the primary key.

    Returns:
        pd.DataFrame: A DataFrame containing only the duplicate rows.
                      Returns an empty DataFrame if no duplicates are found or if primary_key is not in df.
    """
    if primary_key not in df.columns:
        logger.warning(f"Primary key column '{primary_key}' not found in DataFrame. Cannot detect duplicates.")
        return pd.DataFrame(columns=df.columns) # Return empty DataFrame with original columns
    
    duplicates = df[df.duplicated(subset=[primary_key], keep=False)]
    if not duplicates.empty:
        logger.warning(f"Detected {len(duplicates)} duplicate rows based on primary key '{primary_key}'.")
    else:
        logger.info("No duplicate rows found based on primary key.")
    return duplicates



# --- Main Validation Orchestrator ---

def validate_schema(df: pd.DataFrame, source_config: SourceConfig) -> Dict[str, Any]:
    """
    Orchestrates schema and data quality validations for a DataFrame based on SourceConfig.

    Args:
        df (pd.DataFrame): The DataFrame to validate.
        source_config (SourceConfig): The configuration for the data source.

    Returns:
        Dict[str, Any]: A dictionary containing a comprehensive validation report.
                        Example:
                        {
                            "is_valid": bool,
                            "missing_columns": List[str],
                            "duplicate_primary_keys": pd.DataFrame,
                            "null_values_by_column": Dict[str, pd.DataFrame],
                            "summary": str
                        }
    """
    logger.info(f"Starting schema validation for data from '{source_config.source}' (table: '{source_config.destination_table}')")
    
    failure_reasons = []
    validation_report: Dict[str, Any] = {
        "is_valid": True,
        "missing_columns": [],
        "duplicate_primary_keys": pd.DataFrame(),
        "summary": ""
    }

    source_type = (getattr(source_config, 'type', '') or '').strip().lower()

    if source_type == 'parquet' and df.empty:
        validation_report["is_valid"] = False
        failure_reasons.append("Input data is empty")
        logger.error(f"Critical validation failed: Received an empty DataFrame for '{source_config.destination_table or source_config.source}'.")

    # 1. Validate Required Columns
    if hasattr(source_config, 'required_columns') and source_config.required_columns:
        columns_present, missing_cols = validate_required_columns(df, source_config.required_columns)
        if not columns_present:
            validation_report["missing_columns"] = missing_cols
            failure_reasons.append("Missing required columns")
            logger.error(f"Critical validation failed: Missing required columns for '{source_config.destination_table}'.")

    # If critical columns are missing, other validations might not make sense or fail.
    # For now, we continue to collect all issues.
    
    # 3. Detect Duplicates by Primary Key
    if hasattr(source_config, 'primary_key') and source_config.primary_key:
        duplicates_df = detect_duplicates(df, source_config.primary_key)
        if not duplicates_df.empty:
            validation_report["duplicate_primary_keys"] = duplicates_df
            failure_reasons.append("Duplicate primary keys found")

    # Finalize Report
    if failure_reasons:
        validation_report["is_valid"] = False
        validation_report["summary"] = f"Validation failed: {'; '.join(failure_reasons)}."
        logger.warning(f"Schema validation completed with issues for '{source_config.destination_table}'. Summary: {validation_report['summary']}")
    else:
        validation_report["is_valid"] = True
        validation_report["summary"] = "Validation successful."
        logger.info(f"Schema validation completed successfully for '{source_config.destination_table}'.")

    return validation_report

if __name__ == "__main__":
    # Example usage for testing validate_schema.py
    import copy
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

    import sys
    import os
    
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    sys.path.insert(0, project_root)

    try:
        from .config_loader import load_config, IngestionConfig
        from .fetch_data import fetch_data

        config_file_path = os.path.join(project_root, 'configs', 'sources.yaml')
        ingestion_config: IngestionConfig = load_config(config_file_path)

        taxi_zones_config = ingestion_config.sources.get('taxi_zones')

        if taxi_zones_config:
            print("\n--- Running validate_schema for taxi_zones ---")
            df_fetched = fetch_data(taxi_zones_config)
            
            # --- Test Case 1: Valid Data ---
            print("\n--- Running validation on fetched data (should be valid) ---")
            validation_report_valid = validate_schema(df_fetched, taxi_zones_config)
            print("Validation Report (Valid Case):")
            print(f"  Is Valid: {validation_report_valid['is_valid']}")
            print(f"  Summary: {validation_report_valid['summary']}")

            # --- Test Case 2: Missing Columns ---
            print("\n--- Running validation on data with missing columns ---")
            df_missing_col = df_fetched.drop(columns=['Zone'], errors='ignore')
            taxi_zones_config_missing_col = copy.deepcopy(taxi_zones_config)
            taxi_zones_config_missing_col.required_columns = ['LocationID', 'Borough', 'Zone', 'service_zone'] # Ensure Zone is still required
            validation_report_missing = validate_schema(df_missing_col, taxi_zones_config_missing_col)
            print("Validation Report (Missing Column Case):")
            print(f"  Is Valid: {validation_report_missing['is_valid']}")
            print(f"  Missing Columns: {validation_report_missing['missing_columns']}")
            print(f"  Summary: {validation_report_missing['summary']}")
            
            # --- Test Case 3: Duplicate Primary Keys ---
            print("\n--- Running validation on data with duplicate primary keys ---")
            df_duplicate = pd.concat([df_fetched, df_fetched.head(1)], ignore_index=True) # Add a duplicate row
            validation_report_duplicate = validate_schema(df_duplicate, taxi_zones_config)
            print("Validation Report (Duplicate Primary Key Case):")
            print(f"  Is Valid: {validation_report_duplicate['is_valid']}")
            print(f"  Duplicate Primary Keys found: {not validation_report_duplicate['duplicate_primary_keys'].empty}")
            print(f"  Summary: {validation_report_duplicate['summary']}")


            
        else:
            logger.error("'taxi_zones' configuration not found in sources.yaml")

    except Exception as e: # pragma: no cover - example only
        logger.error(f"Failed to run validate_schema example: {e}")
    