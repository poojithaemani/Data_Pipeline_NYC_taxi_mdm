# Project Overview: NYC Taxi Data Pipeline with MDM

## 1. Project Goal

The primary goal of this project is to build a scalable and robust data pipeline on AWS to process the NYC Taxi dataset. It implements a Master Data Management (MDM) system to ensure data quality and consistency for key business entities like taxi zones and vendors. The final output is a set of curated data marts in a data lake, ready for analytics and serving via an API.

## 2. Core Concepts

- **Data Lake Layers (Bronze, Silver, Gold)**: A standard medallion architecture is used to progressively refine data.
  - **Bronze**: Raw, unaltered data ingested from sources.
  - **Silver**: Cleaned, validated, and enriched data. This layer is the "single source of truth."
  - **Gold**: Aggregated data marts tailored for specific business use cases or analytics.
- **Master Data Management (MDM)**: The practice of creating a single, authoritative "golden record" for critical business entities. In this project, MDM is applied to `vendors` and `taxi_zones`.
- **Slowly Changing Dimensions (SCD) Type 2**: A technique to manage changes in master data over time by preserving history. Instead of overwriting records, new versions are inserted, and flags (`is_current`, `effective_date`) are used to identify the current record. This is implemented in the RDS PostgreSQL database.
- **Infrastructure as Code (IaC)**: All AWS resources (S3 buckets, Glue jobs, RDS instances) are defined and managed using Terraform. This ensures consistency, repeatability, and version control for the infrastructure.

## 3. Architecture Deep Dive

The system is composed of two parallel pipelines that interact with each other.

### a. Transactional Data Pipeline (The Main Flow)

This pipeline processes the high-volume taxi trip records.

1.  **Source**: The journey begins with the NYC Taxi dataset (e.g., yellow taxi trip records in Parquet format) landing in the **S3 Bronze** bucket.
2.  **Bronze to Silver (ETL)**: An **AWS Glue PySpark job** (`yellow_taxi_silver_etl.py`) is triggered. Its responsibilities are:
    - **Reading** raw Parquet data from Bronze.
    - **Cleaning**: Removing duplicates, handling nulls, and correcting data types.
    - **Enriching**: Joining with master data from the RDS database to get consistent vendor or zone information.
    - **Partitioning**: Creating `pickup_year` and `pickup_month` columns for efficient querying.
    - **Writing**: Saving the transformed data to the **S3 Silver** bucket in **Delta Lake** format. Delta Lake provides ACID transactions and time travel capabilities to the data lake.
3.  **Silver to Gold (Aggregation)**: Another **Glue ETL job** reads from the Silver Delta table, performs business-level aggregations (e.g., calculating average fare per zone), and writes the results to the **S3 Gold** bucket, also in Delta Lake format.

### b. Reference & Master Data Pipeline (The MDM Flow)

This pipeline manages the master data entities.

1.  **Source**: Reference data, such as a CSV file of vendors or taxi zones, is the input.
2.  **Ingestion**: A Python-based **Ingestion Orchestrator** (`orchestrator.py`) runs on a schedule or is triggered.
    - It reads a `sources.yaml` configuration file to discover what to ingest.
    - It **fetches** the data (e.g., from a URL or local path).
    - It performs initial **validation** and **cleaning**.
    - It uploads the raw/cleaned data to **S3 Bronze** for auditing and reprocessing.
3.  **Mastering (ETL & Database)**:
    - An **AWS Glue PySpark job** (`vendor_etl.py`) reads the reference data from S3.
    - It calculates a `record_hash` for each row to detect changes efficiently.
    - It connects to the **RDS PostgreSQL** database.
    - Crucially, it iterates through each record and calls a **stored procedure** (`sp_upsert_vendor`) in the database.
4.  **SCD Type 2 in PostgreSQL**:
    - The stored procedure contains the logic for the SCD Type 2 upsert.
    - It checks if a record with the same business key (`vendor_id`) and `record_hash` already exists and is current. If so, it does nothing ("NO_CHANGE").
    - If the hash differs, it expires the old record (sets `is_current = false`) and inserts a new one with `is_current = true` ("UPDATED").
    - If the business key is new, it inserts a new record ("INSERTED").
    - This entire process is atomic and managed within the database, ensuring data integrity.

## 4. Data Serving and Consumption

- **Analytics**: **Amazon Athena** is used to run ad-hoc SQL queries directly on the Gold (and Silver) Delta tables in S3. This is ideal for business intelligence and data analysis.
- **API Access**: An **API Gateway** endpoint with a **Lambda** function provides real-time access to the master data stored in the **RDS PostgreSQL** database. This is for applications that need to look up the "current" golden record for a specific entity (e.g., get details for `location_id` 123).

## 5. Key Technologies and Why They Were Chosen

- **Terraform**: For IaC. Ensures the entire platform is reproducible and version-controlled.
- **AWS S3**: Scalable, durable, and cost-effective storage for the data lake.
- **AWS Glue (PySpark)**: A serverless ETL service that scales automatically. PySpark is a powerful tool for large-scale data transformation.
- **Delta Lake**: Provides reliability (ACID transactions) and performance to the S3 data lake, making it behave more like a traditional data warehouse.
- **RDS for PostgreSQL**: A managed relational database used to store the master data. Its transactional capabilities are essential for implementing the SCD Type 2 logic correctly and avoiding race conditions.
- **AWS Lambda & API Gateway**: Provide a serverless, scalable, and low-cost way to expose master data via a REST API.

## 6. Security & Operations

- **Secrets Management**: Database credentials and other secrets are managed using **AWS Secrets Manager**. Terraform and Glue jobs are configured to fetch secrets at runtime, avoiding hardcoded values in code.
- **Database Migrations**: Schema changes for the RDS database are managed through an ordered sequence of SQL migration scripts. The process includes steps for creating indexes concurrently to avoid locking, and clear guidance for safe execution and rollback.
- **Configuration Management**: The ingestion pipeline is driven by a YAML configuration file (`sources.yaml`), making it easy to add new reference data sources without changing the core code. Pydantic is used for robust validation of this configuration.

---
