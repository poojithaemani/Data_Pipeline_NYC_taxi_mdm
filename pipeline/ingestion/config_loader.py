import os
import yaml
import logging
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field, ValidationError

# --- Logger Setup ---
logger = logging.getLogger(__name__)

# --- Pydantic Models for Configuration Validation ---

class SourceConfig(BaseModel):
    """
    Pydantic model for validating the structure of a single data source configuration.
    """
    type: str = Field(..., description="Type of the data source (e.g., 'csv', 'json', 'api').")
    source: str = Field(..., description="Location of the data source (e.g., URL, file path).")
    primary_key: Optional[str] = Field(None, description="The primary key column for the dataset.")
    destination_table: Optional[str] = Field(None, description="The name of the destination table in the database.")
    destination_path: Optional[str] = Field(None, description="Optional S3 destination prefix for the raw object.")
    required_columns: List[str] = Field(..., description="A list of columns that must be present in the dataset.")
    column_mapping: Optional[Dict[str, str]] = Field(None, description="A mapping of source column names to destination column names.")

class IngestionConfig(BaseModel):
    """
    Pydantic model for validating the overall ingestion configuration,
    containing a dictionary of source configurations.
    """
    sources: Dict[str, SourceConfig] = Field(..., description="A dictionary where keys are source names and values are SourceConfig objects.")

# --- Configuration Loader Function ---

def load_config(config_path: str = os.path.join('configs', 'source.yaml')) -> IngestionConfig:
    """
    Loads and validates the ingestion configuration from a YAML file.

    Args:
        config_path (str): The path to the YAML configuration file.
                           Defaults to 'configs/sources.yaml'.

    Returns:
        IngestionConfig: A validated Pydantic object containing the ingestion configuration.

    Raises:
        FileNotFoundError: If the specified configuration file does not exist.
        yaml.YAMLError: If there is an error parsing the YAML file.
        ValidationError: If the loaded configuration does not conform to the IngestionConfig schema.
    """
    if not os.path.exists(config_path):
        alternate_paths = []
        if os.path.basename(config_path) == 'source.yaml':
            alternate_paths.append(config_path.replace('source.yaml', 'sources.yaml'))
        elif os.path.basename(config_path) == 'sources.yaml':
            alternate_paths.append(config_path.replace('sources.yaml', 'source.yaml'))

        for alternate_path in alternate_paths:
            if os.path.exists(alternate_path):
                config_path = alternate_path
                break

        if not os.path.exists(config_path):
            logger.error(f"Configuration file not found at: {config_path}")
            raise FileNotFoundError(f"Configuration file not found at: {config_path}")

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            raw_config = yaml.safe_load(f)
        logger.info(f"Successfully loaded raw configuration from {config_path}")
    except yaml.YAMLError as e:
        logger.error(f"Error parsing YAML configuration file {config_path}: {e}")
        raise
    except Exception as e:
        logger.error(f"An unexpected error occurred while reading {config_path}: {e}")
        raise

    try:
        validated_config = IngestionConfig(**raw_config)
        logger.info("Configuration validated successfully using Pydantic.")
        return validated_config
    except ValidationError as e:
        logger.error(f"Configuration validation failed for {config_path}: {e.errors()}")
        raise
    except Exception as e:
        logger.error(f"An unexpected error occurred during configuration validation: {e}")
        raise

if __name__ == "__main__":
    # Example usage and testing the config loader
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    try:
        # Assuming sources.yaml is in the 'configs' directory relative to where this script is run
        # Or you can specify the absolute path:
        # current_dir = os.path.dirname(os.path.abspath(__file__))
        # config_file_path = os.path.join(current_dir, '..', '..', 'configs', 'sources.yaml')
        # config = load_config(config_file_path)

        # For this specific context, where I'm operating from the root of Data_Pipeline_NYC_taxi_mdm
        # and configs is a direct subdirectory of Data_Pipeline_NYC_taxi_mdm
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        config_file_path = os.path.join(project_root, 'configs', 'sources.yaml')
        
        print(f"Attempting to load config from: {config_file_path}")
        config = load_config(config_file_path)
        
        logger.info("Configuration loaded and validated successfully:")
        for source_name, source_data in config.sources.items():
            logger.info(f"  Source: {source_name}")
            logger.info(f"    Type: {source_data.type}")
            logger.info(f"    Source URL: {source_data.source}")
            logger.info(f"    Primary Key: {source_data.primary_key}")
            logger.info(f"    Destination Table: {source_data.destination_table}")
            logger.info(f"    Required Columns: {source_data.required_columns}")

    except (FileNotFoundError, yaml.YAMLError, ValidationError) as e:
        logger.error(f"Failed to load configuration: {e}")
    except Exception as e:
        logger.error(f"An unexpected error occurred: {e}")
