# AWS Glue Silver ETL for Yellow Taxi

## 1. Glue PySpark script

Use the script at [pipeline/glue/jobs/yellow_taxi_silver_etl.py](../pipeline/glue/jobs/yellow_taxi_silver_etl.py).

## 2. Exact AWS Glue Job configuration

- Python version: 3
- Glue version: 4.0
- Worker type: G.1X
- Number of workers: 2
- IAM role: the existing Glue execution role that has S3 and CloudWatch access
- Temporary directory: s3://emani-nyc-taxi-bucket/glue-temp/
- Job bookmark: disabled
- Script file: upload this Python script to S3, for example s3://emani-nyc-taxi-bucket/glue-scripts/yellow_taxi_silver_etl.py
- Job arguments:
  - --JOB_NAME yellow_taxi_silver_etl
  - --bronze_path s3://emani-nyc-taxi-bucket/bronze/transactions/yellow_taxi/
  - --silver_path s3://emani-nyc-taxi-bucket/silver/yellow_taxi/

## 3. Required Spark configurations for Delta Lake

Add these job parameters or Spark conf entries:

- --conf spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension
- --conf spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog
- --conf spark.hadoop.mapreduce.fileoutputcommitter.algorithm.version=2

## 4. Required IAM permissions

The Glue execution role should allow:

- s3:ListBucket on arn:aws:s3:::emani-nyc-taxi-bucket
- s3:GetObject and s3:PutObject on arn:aws:s3:::emani-nyc-taxi-bucket/\*
- logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents
- glue:StartJobRun (if triggered by another service)

## 5. Folder structure after execution

```text
bronze/
    transactions/
        yellow_taxi/

silver/
    yellow_taxi/
        pickup_year=2025/
            pickup_month=01/
```

## 6. Transformation summary

- read_data(): reads raw Parquet data from Bronze.
- clean_data(): removes duplicates, drops rows with nulls in required columns, removes invalid values, and casts columns to the correct data types.
- add_partitions(): creates pickup_year and pickup_month from tpep_pickup_datetime.
- write_delta(): writes the cleaned dataset as Delta Lake, partitioned by pickup_year and pickup_month, with Snappy compression.
- main(): orchestrates the job and handles logging and exception handling.
