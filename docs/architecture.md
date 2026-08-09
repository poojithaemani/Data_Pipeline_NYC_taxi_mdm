# Data Pipeline Architecture for NYC Taxi MDM

                    +----------------------+
                    |    Source Data       |
                    |  NYC Taxi CSV Files  |
                    +----------+-----------+
                               |
                               |
                               v
                    +----------------------+
                    |        Amazon S3     |
                    |----------------------|
                    | Bronze Layer         |
                    | Raw CSV Files        |
                    +----------+-----------+
                               |
                    Glue Crawlers (Metadata)
                               |
                               v
                    +----------------------+
                    |     AWS Glue Data    |
                    |       Catalog        |
                    +----------+-----------+
                               |
                               |
                    AWS Glue ETL Jobs
                               |
                               v
                    +------------------------+
                    |    Golden Zone ETL     |
                    |  golden_zone_etl.py    |
                    +-----------+------------+
                               |
                               |
                            Read CSV
                            Clean Data
                            Generate Hash
                               |
                               |
                               v
                    +----------------------+
                    | Aurora PostgreSQL    |
                    |----------------------|
                    | Stored Procedures    |
                    |                      |
                    | sp_upsert_golden()   |
                    +----------+-----------+
                               |
                               |
                               v
                    +-----------------------------+
                    | MDM Database                |
                    |-----------------------------|
                    | golden_zones                |
                    | taxi_zones                  |
                    | zone_matches                |
                    | SCD Type 2 History          |
                    +----------+------------------+
                               |
                               |
                          Glue Crawlers
                               |
                               v
                    +-----------------------------+
                    | AWS Glue Catalog            |
                    | Gold Tables                 |
                    +-------------+---------------+
                               |
                               |
                    +----------+-----------+
                    | Amazon Athena       |
                    | SQL Analytics       |
                    +----------+-----------+
                               |
                               |
                               v
                    +----------------------+
                    | Amazon QuickSight    |
                    | Dashboards           |
                    +----------------------+

This architecture consists of two main data flows:

1.  **Transactional Data Pipeline**: Processes high-volume NYC Taxi trip records.
2.  **Reference Data Ingestion**: Manages and masters reference datasets like taxi zones and vendors.

```mermaid
graph TD
    subgraph "Infrastructure as Code"
        Terraform("Terraform")
    end

    subgraph "Transactional Data Pipeline (Batch)"
        direction LR
        subgraph "Bronze Layer (Raw Data)"
            S3_Bronze_T["S3 Bronze (Parquet)"]
        end
        subgraph "Silver Layer (Cleaned & Enriched)"
            Glue_ETL_Silver["Glue ETL (PySpark)<br/>- Clean & Validate<br/>- Enrich w/ Master Data<br/>- Convert to Delta"]
            S3_Silver["S3 Silver (Delta Lake)"]
        end
        subgraph "Gold Layer (Aggregated)"
            Glue_ETL_Gold["Glue ETL (PySpark)<br/>- Business Aggregations"]
            S3_Gold["S3 Gold (Delta Lake)"]
        end
        S3_Bronze_T --> Glue_ETL_Silver --> S3_Silver --> Glue_ETL_Gold --> S3_Gold
    end

    subgraph "Reference & Master Data Pipeline (MDM)"
        direction TB
        subgraph "Sources"
            Ref_Sources("Reference Data Sources<br/>(e.g., CSV, API)")
        end
        subgraph "Ingestion & Mastering"
            Ingestion_Orchestrator("Ingestion Orchestrator<br/>(Python)")
            S3_Bronze_R["S3 Bronze (Raw)"]
            Glue_ETL_GoldenZone["Glue ETL (PySpark)<br/>- Golden Zone SCD Type 2 Logic<br/>- Calls sp_upsert_golden_zone"]
            RDS_PG["RDS PostgreSQL<br/>(Golden Zones - SCD2)"]
        end
        Ref_Sources --> Ingestion_Orchestrator --> S3_Bronze_R
        S3_Bronze_R --> Glue_ETL_GoldenZone --> RDS_PG
    end

    subgraph "Data Serving & Analytics"
        Athena["Athena on S3 Gold"]
        API_GW["API Gateway"] --> Lambda["Lambda"] --> RDS_PG
    end

    Terraform --> S3_Bronze_T & S3_Bronze_R & Glue_ETL_Silver & Glue_ETL_Gold & RDS_PG & API_GW & Lambda
    RDS_PG -.-> Glue_ETL_Silver
    S3_Gold --> Athena
```
