
import logging
import pandas as pd
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.dialects.postgresql import insert

from services.database.connection import engine, SessionLocal
from pipeline.ingestion.config_loader import load_config
from sqlalchemy import Table, MetaData

# Configure logging
logger = logging.getLogger(__name__)

def load_to_postgres(df: pd.DataFrame, table_name: str, primary_key: str):
    """
    Upserts a pandas DataFrame to a PostgreSQL table.

    Args:
        df (pd.DataFrame): The DataFrame to upsert.
        table_name (str): The name of the target table in PostgreSQL.
        primary_key (str): The primary key of the target table.
    """
    session: Session = SessionLocal()
    try:
        logger.info(f"Starting upsert process for table '{table_name}'.")
        logger.info("DataFrame columns: %s", df.columns.tolist())

        # Convert DataFrame to a list of dictionaries
        data_to_insert = df.to_dict(orient='records')

        if not data_to_insert:
            logger.info("DataFrame is empty, nothing to upsert.")
            return

        # Reflect the table from the database
        metadata = MetaData()
        table = Table(table_name, metadata, autoload_with=engine)

        # Create the insert statement with ON CONFLICT DO UPDATE
        stmt = insert(table).values(data_to_insert)
        
        # Define the columns to update on conflict
        update_columns = {
            col.name: col for col in stmt.excluded if col.name != primary_key
        }
        
        stmt = stmt.on_conflict_do_update(
            index_elements=[primary_key],
            set_=update_columns
        )

        # Execute the statement
        session.execute(stmt)
        session.commit()
        logger.info(f"Successfully upserted {len(data_to_insert)} records into '{table_name}'.")

    except SQLAlchemyError as e:
        logger.error(f"Database error during upsert to '{table_name}': {e}")
        session.rollback()
        raise
    except Exception as e:
        logger.error(f"An unexpected error occurred during the upsert process: {e}")
        session.rollback()
        raise
    finally:
        session.close()
        logger.info("Database session closed.")

if __name__ == '__main__':
    # Example Usage
    import sys
    from pathlib import Path
    project_root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(project_root))
    
    logging.basicConfig(level=logging.INFO)

    try:
        # Since we modified path, we need to re-import to use the correct modules
        from pipeline.ingestion.config_loader import load_config

        # Load configuration to get table details
        ingestion_config = load_config()
        source_name = 'taxi_zones' # Assuming this is the source we're working with
        if source_name in ingestion_config.sources:
            config = ingestion_config.sources[source_name]
            table_name = config.destination_table
            pk = config.primary_key

            # Create a sample DataFrame for testing
            # This data should match the schema of the 'taxi_zones' table
            data = {
                'location_id': [1, 2, 264],
                'Borough': ['EWR', 'Queens', 'Unknown'],
                'Zone': ['Newark Airport', 'Jamaica Bay', 'N/A'],
                'service_zone': ['EWR', 'Boro Zone', 'N/A']
            }
            sample_df = pd.DataFrame(data)

            logger.info(f"Attempting to load sample data into '{table_name}' with primary key '{pk}'.")
            load_to_postgres(sample_df, table_name, pk)
            logger.info("Sample data loaded successfully.")
            
            # Example of updating an existing record
            update_data = {
                'location_id': [1],
                'Borough': ['EWR'],
                'Zone': ['Newark International Airport'], # Updated Zone
                'service_zone': ['EWR']
            }
            update_df = pd.DataFrame(update_data)
            logger.info("Attempting to update a record.")
            load_to_postgres(update_df, table_name, pk)
            logger.info("Record updated successfully.")

        else:
            logger.error(f"Source '{source_name}' not found in configuration.")

    except Exception as e:
        logger.error(f"An error occurred in the main execution block: {e}")
