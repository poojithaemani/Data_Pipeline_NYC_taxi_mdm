
import os
import boto3
import logging
from io import BytesIO, StringIO
import pandas as pd
from botocore.exceptions import NoCredentialsError, PartialCredentialsError, ClientError

# Configure logging
logger = logging.getLogger(__name__)

def upload_to_s3(df: pd.DataFrame, bucket_name: str, object_key: str):
    """
    Uploads a pandas DataFrame to an S3 bucket as a CSV file.

    Args:
        df (pd.DataFrame): The DataFrame to upload.
        bucket_name (str): The name of the S3 bucket.
        object_key (str): The key for the object in the S3 bucket.

    Returns:
        bool: True if the upload was successful, False otherwise.
    """
    try:
        if object_key.lower().endswith('.parquet'):
            parquet_buffer = BytesIO()
            df.to_parquet(parquet_buffer, index=False)
            payload = parquet_buffer.getvalue()
            content_type = 'application/octet-stream'
        else:
            csv_buffer = StringIO()
            df.to_csv(csv_buffer, index=False)
            payload = csv_buffer.getvalue().encode('utf-8')
            content_type = 'text/csv'

        # Create an S3 client
        s3_client = boto3.client('s3')

        # Upload the content
        s3_client.put_object(
            Bucket=bucket_name,
            Key=object_key,
            Body=payload,
            ContentType=content_type
        )
        logger.info(f"Successfully uploaded data to s3://{bucket_name}/{object_key}")
        return True
    except (NoCredentialsError, PartialCredentialsError):
        logger.error("AWS credentials not found. Please configure your credentials.")
        return False
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchBucket':
            logger.error(f"Bucket '{bucket_name}' does not exist.")
        else:
            logger.error(f"An S3 client error occurred: {e}")
        return False
    except Exception as e:
        logger.error(f"An unexpected error occurred during S3 upload: {e}")
        return False

if __name__ == '__main__':
    # Example Usage
    import sys
    from pathlib import Path
    project_root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(project_root))

    logging.basicConfig(level=logging.INFO)

    # Create a sample DataFrame
    data = {'col1': [1, 2], 'col2': [3, 4]}
    sample_df = pd.DataFrame(data)

    # Get bucket name from environment variable
    s3_bucket = os.getenv('AWS_S3_BUCKET')
    if not s3_bucket:
        logger.error("AWS_S3_BUCKET environment variable not set.")
    else:
        # Define the S3 object key
        s3_object_key = "bronze/reference/taxi_zones/taxi_zones.csv"
        
        # Upload the DataFrame
        success = upload_to_s3(sample_df, s3_bucket, s3_object_key)
        if success:
            logger.info("Sample DataFrame uploaded successfully.")
        else:
            logger.error("Failed to upload sample DataFrame.")
